<%@ page import="java.util.*, java.text.*, com.mongodb.*, com.mongodb.client.*, org.bson.*, com.mongodb.client.model.*" %>
<%@ page import="static com.mongodb.client.model.Filters.*" %>
<%@ page import="static com.mongodb.client.model.Aggregates.*" %>
<%@ page import="static com.mongodb.client.model.Accumulators.*" %>
<%@ page import="static com.mongodb.client.model.Sorts.*" %>
<%@ page import="java.io.*" %>
<%@ page import="org.bson.types.ObjectId" %>
<%@ page import="org.bson.conversions.Bson" %>
<%
    // Check if user is logged in
    String loggedInUserId = (String) session.getAttribute("userId");
    if (loggedInUserId == null) {
        response.sendRedirect("login.jsp");
        return;
    }

    List<Document> categoryStats = new ArrayList<>();
    String errorMessage = null;
    double grandTotal = 0;

    // MongoDB connection - Using your working pattern
    MongoClient mongoClient = null;
    MongoDatabase database = null;
    MongoCollection<Document> expensesCollection = null;
    MongoCollection<Document> categoriesCollection = null;
    
    try {
        Properties props = new Properties();
        props.load(getServletContext().getResourceAsStream("/WEB-INF/config.properties"));
        String connectionString = props.getProperty("mongodb.uri", "mongodb://localhost:27017/finance_tracker");
        
        mongoClient = MongoClients.create(connectionString);
        database = mongoClient.getDatabase("finance_tracker");
        expensesCollection = database.getCollection("expenses");
        categoriesCollection = database.getCollection("categories");
        
    } catch (Exception e) {
        errorMessage = "Database connection failed: " + e.getMessage();
    }

    // Load statistics
    if (mongoClient != null && loggedInUserId != null) {
        try {
            ObjectId userObjectId = new ObjectId(loggedInUserId);
            
            // Get categories with their colors - FIXED: Proper cursor handling
            Map<String, String> categoryColors = new HashMap<>();
            Map<String, String> categoryNames = new HashMap<>();
            FindIterable<Document> categoriesCursor = categoriesCollection.find(eq("user_id", userObjectId));
            
            // Properly iterate through cursor
            MongoCursor<Document> cursor = categoriesCursor.iterator();
            while (cursor.hasNext()) {
                Document category = cursor.next();
                String catId = category.getObjectId("_id").toString();
                categoryNames.put(catId, category.getString("name"));
                categoryColors.put(catId, category.getString("color"));
            }
            cursor.close();
            
            // Get expense statistics by category
            if (!categoryColors.isEmpty()) {
                List<ObjectId> categoryIds = new ArrayList<>();
                for (String catId : categoryColors.keySet()) {
                    categoryIds.add(new ObjectId(catId));
                }
                
                // Create aggregation pipeline
                List<Bson> pipeline = Arrays.asList(
                    match(in("category_id", categoryIds)),
                    group("$category_id", sum("total", "$amount"), sum("count", 1)),
                    sort(descending("total"))
                );
                
                AggregateIterable<Document> statsCursor = expensesCollection.aggregate(pipeline);
                
                // Properly iterate through aggregation cursor
                MongoCursor<Document> statsIterator = statsCursor.iterator();
                while (statsIterator.hasNext()) {
                    Document stat = statsIterator.next();
                    String catId = stat.getObjectId("_id").toString();
                    Document category = categoriesCollection.find(eq("_id", new ObjectId(catId))).first();
                    if (category != null) {
                        stat.put("name", category.getString("name"));
                        stat.put("color", categoryColors.get(catId));
                        categoryStats.add(stat);
                        grandTotal += stat.getDouble("total");
                    }
                }
                statsIterator.close();
                
                // Calculate percentages
                for (Document stat : categoryStats) {
                    double percentage = grandTotal > 0 ? (stat.getDouble("total") / grandTotal) * 100 : 0;
                    stat.put("percentage", percentage);
                }
            }
            
        } catch (Exception e) {
            errorMessage = "Database error: " + e.getMessage();
        } finally {
            if (mongoClient != null) {
                mongoClient.close();
            }
        }
    }
    
    DecimalFormat df = new DecimalFormat("#,##0.00");
    DecimalFormat pctFormat = new DecimalFormat("#0.0");
    
    // Prepare data for pie chart
    StringBuilder chartLabels = new StringBuilder();
    StringBuilder chartData = new StringBuilder();
    StringBuilder chartColors = new StringBuilder();
    StringBuilder chartPercentages = new StringBuilder();
    
    for (int i = 0; i < categoryStats.size(); i++) {
        Document stat = categoryStats.get(i);
        if (i > 0) {
            chartLabels.append(",");
            chartData.append(",");
            chartColors.append(",");
            chartPercentages.append(",");
        }
        chartLabels.append("'").append(stat.getString("name")).append("'");
        chartData.append(stat.getDouble("total"));
        chartColors.append("'").append(stat.getString("color")).append("'");
        chartPercentages.append(stat.getDouble("percentage"));
    }
%>

<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>Personal Finance Tracker - Statistics</title>
    
    <link rel="icon" type="image/png" href="icon.png">
    <link href="https://cdn.jsdelivr.net/npm/bootstrap@5.3.3/dist/css/bootstrap.min.css" rel="stylesheet">
    <link href="https://cdnjs.cloudflare.com/ajax/libs/font-awesome/6.0.0/css/all.min.css" rel="stylesheet">
    <script src="https://cdn.jsdelivr.net/npm/chart.js"></script>
    
    <style>
        :root {
            --primary-color: #38bdf8;
            --light-bg: #f8f9fa;
            --dark-bg: #1a1d23;
            --dark-card: #2d3139;
            --dark-text: #e9ecef;
        }
        
        /* Dark Mode Styles */
        body.dark-mode {
            background: var(--dark-bg);
            color: var(--dark-text);
        }
        
        body.dark-mode .app-header {
            background: linear-gradient(135deg, #1e3a8a 0%, #1e40af 100%);
        }
        
        body.dark-mode .chart-container,
        body.dark-mode .stat-card {
            background: var(--dark-card);
            color: var(--dark-text);
            box-shadow: 0 8px 25px rgba(0,0,0,0.3);
        }
        
        body.dark-mode .bottom-nav {
            background: var(--dark-card);
            border-top-color: #374151;
        }
        
        body.dark-mode .nav-item {
            color: #9ca3af;
        }
        
        body.dark-mode .nav-item.active {
            background: var(--primary-color);
            color: white;
        }
        
        body.dark-mode .empty-state {
            color: #9ca3af;
        }
        
        body {
            background: var(--light-bg);
            font-family: 'Segoe UI', Tahoma, Geneva, Verdana, sans-serif;
            padding-bottom: 80px;
            transition: background-color 0.3s ease, color 0.3s ease;
        }
        
        .app-header {
            background: linear-gradient(135deg, #38bdf8 0%, #0ea5e9 100%);
            color: white;
            padding: 1rem 0;
            margin-bottom: 2rem;
            box-shadow: 0 4px 12px rgba(0,0,0,0.1);
            position: relative;
            z-index: 100;
        }
        
        .header-content {
            display: flex;
            align-items: center;
            justify-content: space-between;
            position: relative;
        }
        
        .app-title {
            font-weight: 800;
            margin: 0;
            font-size: 1.8rem;
            background: linear-gradient(45deg, #fff 0%, #f0f8ff 100%);
            -webkit-background-clip: text;
            -webkit-text-fill-color: transparent;
            background-clip: text;
            text-shadow: 0 2px 4px rgba(0,0,0,0.1);
            flex: 1;
            text-align: center;
            margin: 0 60px;
        }
        
        /* Hamburger Menu */
        .hamburger-menu {
            position: relative;
            z-index: 1000;
        }
        
        .hamburger-btn {
            background: rgba(255,255,255,0.2);
            border: 2px solid rgba(255,255,255,0.3);
            color: white;
            width: 44px;
            height: 44px;
            border-radius: 12px;
            display: flex;
            flex-direction: column;
            justify-content: center;
            align-items: center;
            cursor: pointer;
            transition: all 0.3s ease;
            backdrop-filter: blur(10px);
        }
        
        .hamburger-btn:hover {
            background: rgba(255,255,255,0.3);
            transform: scale(1.05);
        }
        
        .hamburger-icon {
            width: 20px;
            height: 18px;
            position: relative;
            transform: rotate(0deg);
            transition: .5s ease-in-out;
        }
        
        .hamburger-icon span {
            display: block;
            position: absolute;
            height: 3px;
            width: 100%;
            background: white;
            border-radius: 3px;
            opacity: 1;
            left: 0;
            transform: rotate(0deg);
            transition: .25s ease-in-out;
        }
        
        .hamburger-icon span:nth-child(1) { top: 0px; }
        .hamburger-icon span:nth-child(2) { top: 7px; }
        .hamburger-icon span:nth-child(3) { top: 14px; }
        
        .hamburger-btn.active .hamburger-icon span:nth-child(1) {
            top: 7px;
            transform: rotate(135deg);
        }
        
        .hamburger-btn.active .hamburger-icon span:nth-child(2) {
            opacity: 0;
            left: -60px;
        }
        
        .hamburger-btn.active .hamburger-icon span:nth-child(3) {
            top: 7px;
            transform: rotate(-135deg);
        }
        
        /* Theme Toggle */
        .theme-toggle {
            background: rgba(255,255,255,0.2);
            border: 2px solid rgba(255,255,255,0.3);
            color: white;
            width: 44px;
            height: 44px;
            border-radius: 12px;
            display: flex;
            align-items: center;
            justify-content: center;
            cursor: pointer;
            transition: all 0.3s ease;
            backdrop-filter: blur(10px);
        }
        
        .theme-toggle:hover {
            background: rgba(255,255,255,0.3);
            transform: scale(1.05);
        }
        
        /* Sidebar Menu */
        .sidebar-menu {
            position: fixed;
            top: 0;
            left: -320px;
            width: 300px;
            height: 100vh;
            background: white;
            box-shadow: 5px 0 25px rgba(0,0,0,0.1);
            transition: all 0.3s ease;
            z-index: 999;
            padding: 80px 1rem 2rem;
            overflow-y: auto;
        }
        
        body.dark-mode .sidebar-menu {
            background: var(--dark-card);
            color: var(--dark-text);
        }
        
        .sidebar-menu.open {
            left: 0;
        }
        
        .sidebar-menu .menu-item {
            display: flex;
            align-items: center;
            padding: 1rem;
            margin-bottom: 0.5rem;
            border-radius: 10px;
            color: #333;
            text-decoration: none;
            transition: all 0.3s ease;
            border: none;
            background: none;
            width: 100%;
            text-align: left;
            font-size: 1rem;
            cursor: pointer;
        }
        
        body.dark-mode .sidebar-menu .menu-item {
            color: var(--dark-text);
        }
        
        .sidebar-menu .menu-item:hover {
            background: rgba(0, 0, 0, 0.05);
            color: #333;
            transform: translateX(5px);
        }
        
        body.dark-mode .sidebar-menu .menu-item:hover {
            background: rgba(255, 255, 255, 0.1);
            color: var(--dark-text);
        }
        
        .sidebar-menu .menu-item i {
            width: 20px;
            margin-right: 1rem;
            font-size: 1.1rem;
        }
        
        .menu-overlay {
            position: fixed;
            top: 0;
            left: 0;
            width: 100%;
            height: 100%;
            background: rgba(0,0,0,0.5);
            z-index: 998;
            opacity: 0;
            visibility: hidden;
            transition: all 0.3s ease;
        }
        
        .menu-overlay.active {
            opacity: 1;
            visibility: visible;
        }
        
        .stats-container {
            max-width: 1200px;
            margin: 0 auto;
            padding: 0 1rem;
        }
        
        .chart-container {
            background: white;
            border-radius: 16px;
            padding: 2rem;
            margin-bottom: 2rem;
            box-shadow: 0 8px 25px rgba(0,0,0,0.1);
            text-align: center;
        }
        
        .chart-wrapper {
            position: relative;
            height: 400px;
            margin: 0 auto;
        }
        
        .stats-grid {
            display: grid;
            grid-template-columns: repeat(auto-fit, minmax(300px, 1fr));
            gap: 1.5rem;
            margin-top: 2rem;
        }
        
        .stat-card {
            background: white;
            border-radius: 12px;
            padding: 1.5rem;
            box-shadow: 0 4px 6px rgba(0,0,0,0.07);
            border-left: 4px solid var(--category-color);
        }
        
        .stat-header {
            display: flex;
            justify-content: space-between;
            align-items: center;
            margin-bottom: 1rem;
        }
        
        .stat-title {
            font-weight: 600;
            margin: 0;
            font-size: 1.1rem;
        }
        
        .stat-amount {
            font-weight: 700;
            color: #dc3545;
            font-size: 1.3rem;
        }
        
        .progress {
            height: 12px;
            border-radius: 6px;
            margin: 0.5rem 0;
            background: #f8f9fa;
        }
        
        body.dark-mode .progress {
            background: #374151;
        }
        
        .progress-bar {
            border-radius: 6px;
        }
        
        .stat-details {
            display: flex;
            justify-content: space-between;
            font-size: 0.9rem;
            color: #6c757d;
            margin-top: 0.5rem;
        }
        
        body.dark-mode .stat-details {
            color: #9ca3af;
        }
        
        .category-color {
            display: inline-block;
            width: 12px;
            height: 12px;
            border-radius: 50%;
            margin-right: 0.5rem;
        }
        
        .total-display {
            text-align: center;
            margin-bottom: 2rem;
        }
        
        .total-amount {
            font-size: 2.5rem;
            font-weight: 800;
            color: var(--primary-color);
            margin-bottom: 0.5rem;
        }
        
        .total-label {
            font-size: 1rem;
            color: #6c757d;
            text-transform: uppercase;
            letter-spacing: 1px;
        }
        
        body.dark-mode .total-label {
            color: #9ca3af;
        }
        
        .empty-state {
            text-align: center;
            padding: 3rem 1rem;
            color: #6c757d;
        }
        
        .empty-state i {
            font-size: 3rem;
            margin-bottom: 1rem;
        }
        
        .chart-legend {
            display: flex;
            flex-wrap: wrap;
            justify-content: center;
            gap: 1rem;
            margin-top: 2rem;
        }
        
        .legend-item {
            display: flex;
            align-items: center;
            padding: 0.5rem 1rem;
            background: #f8f9fa;
            border-radius: 8px;
            font-size: 0.9rem;
        }
        
        body.dark-mode .legend-item {
            background: #374151;
            color: var(--dark-text);
        }
        
        .legend-color {
            width: 16px;
            height: 16px;
            border-radius: 4px;
            margin-right: 0.5rem;
        }
        
        /* Bottom Navigation */
        .bottom-nav {
            position: fixed;
            bottom: 0;
            left: 0;
            right: 0;
            background: white;
            border-top: 1px solid #dee2e6;
            padding: 0.5rem;
            z-index: 1000;
            box-shadow: 0 -2px 10px rgba(0,0,0,0.1);
        }
        
        .nav-grid {
            display: grid;
            grid-template-columns: repeat(4, 1fr);
            gap: 0.5rem;
        }
        
        .nav-item {
            display: flex;
            flex-direction: column;
            align-items: center;
            padding: 0.5rem;
            border: none;
            background: none;
            border-radius: 8px;
            transition: all 0.3s ease;
            color: #6c757d;
            text-decoration: none;
            cursor: pointer;
        }
        
        .nav-item.active {
            background: var(--primary-color);
            color: white;
        }
        
        .nav-item:hover {
            background: #e9ecef;
            color: var(--primary-color);
        }
        
        .nav-item.active:hover {
            background: var(--secondary-color);
            color: white;
        }
        
        .nav-icon {
            font-size: 1.2rem;
            margin-bottom: 0.25rem;
        }
        
        .nav-label {
            font-size: 0.7rem;
            font-weight: 600;
        }
        
        @media (max-width: 768px) {
            .app-title {
                font-size: 1.5rem;
                margin: 0 50px;
            }
            
            .chart-wrapper {
                height: 300px;
            }
            
            .total-amount {
                font-size: 2rem;
            }
            
            .stats-grid {
                grid-template-columns: 1fr;
            }
        }
        
        @media (max-width: 480px) {
            .app-title {
                font-size: 1.3rem;
                margin: 0 45px;
            }
        }
    </style>
</head>
<body>
    <!-- Header -->
    <div class="app-header">
        <div class="container">
            <div class="header-content">
                <!-- Hamburger Menu -->
                <div class="hamburger-menu">
                    <button class="hamburger-btn" id="hamburgerBtn" aria-label="Main menu">
                        <div class="hamburger-icon">
                            <span></span>
                            <span></span>
                            <span></span>
                        </div>
                    </button>
                </div>

                <!-- App Title -->
                <h1 class="app-title">Statistics</h1>

                <!-- Theme Toggle -->
                <div class="theme-toggle" id="themeToggle">
                    <i class="fas fa-moon"></i>
                </div>
            </div>
        </div>
    </div>

    <!-- Sidebar Menu -->
    <div class="sidebar-menu" id="sidebarMenu">
        <button class="menu-item" onclick="window.location.href='tracker.jsp'">
            <i class="fas fa-home"></i>
            <span>Dashboard</span>
        </button>
        <button class="menu-item" onclick="window.location.href='categories.jsp'">
            <i class="fas fa-folder"></i>
            <span>Categories</span>
        </button>
        <button class="menu-item" onclick="window.location.href='recent.jsp'">
            <i class="fas fa-history"></i>
            <span>Recent</span>
        </button>
        <button class="menu-item" onclick="downloadChart()">
            <i class="fas fa-download"></i>
            <span>Download Chart</span>
        </button>
        <button class="menu-item" onclick="printReport()">
            <i class="fas fa-print"></i>
            <span>Print Report</span>
        </button>
        <div style="margin-top: 2rem; padding-top: 1rem; border-top: 1px solid #dee2e6;">
            <button class="menu-item text-danger" onclick="logout()">
                <i class="fas fa-sign-out-alt"></i>
                <span>Log Out</span>
            </button>
        </div>
    </div>

    <!-- Menu Overlay -->
    <div class="menu-overlay" id="menuOverlay"></div>

    <!-- Alert Messages -->
    <% if (errorMessage != null) { %>
    <div class="alert alert-danger alert-dismissible fade show mx-3" role="alert">
        <i class="fas fa-exclamation-triangle me-2"></i><%= errorMessage %>
        <button type="button" class="btn-close" data-bs-dismiss="alert"></button>
    </div>
    <% } %>

    <div class="stats-container">
        <% if (categoryStats.isEmpty()) { %>
        <div class="empty-state">
            <i class="fas fa-chart-pie"></i>
            <h4>No Data Available</h4>
            <p>Add some expenses to see statistics.</p>
        </div>
        <% } else { %>
            <!-- Total Spending Display -->
            <div class="total-display">
                <div class="total-amount">&#8377;<%= df.format(grandTotal) %></div>
                <div class="total-label">Total Spending</div>
            </div>

            <!-- Pie Chart -->
            <div class="chart-container">
                <h3 class="mb-4">
                    <i class="fas fa-chart-pie me-2"></i>
                    Spending by Category
                </h3>
                <div class="chart-wrapper">
                    <canvas id="pieChart"></canvas>
                </div>
                
                <!-- Chart Legend -->
                <div class="chart-legend">
                    <% for (Document stat : categoryStats) { 
                        String categoryName = stat.getString("name");
                        double percentage = stat.getDouble("percentage");
                        String color = stat.getString("color");
                    %>
                    <div class="legend-item">
                        <div class="legend-color" style="background: <%= color %>"></div>
                        <span><%= categoryName %> (<%= pctFormat.format(percentage) %>%)</span>
                    </div>
                    <% } %>
                </div>
            </div>

            <!-- Detailed Statistics -->
            <div class="stats-grid">
                <% for (Document stat : categoryStats) { 
                    String categoryName = stat.getString("name");
                    double total = stat.getDouble("total");
                    int count = stat.getInteger("count");
                    double percentage = stat.getDouble("percentage");
                    String color = stat.getString("color");
                %>
                <div class="stat-card" style="--category-color: <%= color %>">
                    <div class="stat-header">
                        <h3 class="stat-title">
                            <span class="category-color" style="background: <%= color %>"></span>
                            <%= categoryName %>
                        </h3>
                        <div class="stat-amount">&#8377;<%= df.format(total) %></div>
                    </div>
                    
                    <div class="progress">
                        <div class="progress-bar" 
                             style="width: <%= percentage %>%; background-color: <%= color %>">
                        </div>
                    </div>
                    
                    <div class="stat-details">
                        <span><%= pctFormat.format(percentage) %>% of total</span>
                        <span><%= count %> transaction<%= count != 1 ? "s" : "" %></span>
                    </div>
                </div>
                <% } %>
            </div>
        <% } %>
    </div>

    <!-- Bottom Navigation -->
    <nav class="bottom-nav">
        <div class="container">
            <div class="nav-grid">
                <a href="tracker.jsp" class="nav-item">
                    <i class="fas fa-home nav-icon"></i>
                    <span class="nav-label">Home</span>
                </a>
                <a href="categories.jsp" class="nav-item">
                    <i class="fas fa-folder nav-icon"></i>
                    <span class="nav-label">Categories</span>
                </a>
                <a href="statistics.jsp" class="nav-item active">
                    <i class="fas fa-chart-pie nav-icon"></i>
                    <span class="nav-label">Statistics</span>
                </a>
                <a href="recent.jsp" class="nav-item">
                    <i class="fas fa-history nav-icon"></i>
                    <span class="nav-label">Recent</span>
                </a>
            </div>
        </div>
    </nav>

    <script src="https://cdn.jsdelivr.net/npm/bootstrap@5.3.3/dist/js/bootstrap.bundle.min.js"></script>
    <script>
        // Theme Management
        const themeToggle = document.getElementById('themeToggle');
        const themeIcon = themeToggle.querySelector('i');
        
        const currentTheme = localStorage.getItem('theme') || 'light';
        if (currentTheme === 'dark') {
            document.body.classList.add('dark-mode');
            themeIcon.classList.remove('fa-moon');
            themeIcon.classList.add('fa-sun');
        }
        
        themeToggle.addEventListener('click', () => {
            document.body.classList.toggle('dark-mode');
            
            if (document.body.classList.contains('dark-mode')) {
                localStorage.setItem('theme', 'dark');
                themeIcon.classList.remove('fa-moon');
                themeIcon.classList.add('fa-sun');
            } else {
                localStorage.setItem('theme', 'light');
                themeIcon.classList.remove('fa-sun');
                themeIcon.classList.add('fa-moon');
            }
        });

        // Hamburger Menu Functionality
        const hamburgerBtn = document.getElementById('hamburgerBtn');
        const sidebarMenu = document.getElementById('sidebarMenu');
        const menuOverlay = document.getElementById('menuOverlay');

        function toggleMenu() {
            hamburgerBtn.classList.toggle('active');
            sidebarMenu.classList.toggle('open');
            menuOverlay.classList.toggle('active');
            
            document.body.style.overflow = sidebarMenu.classList.contains('open') ? 'hidden' : '';
        }

        if (hamburgerBtn) hamburgerBtn.addEventListener('click', toggleMenu);
        if (menuOverlay) menuOverlay.addEventListener('click', toggleMenu);

        document.querySelectorAll('.sidebar-menu .menu-item').forEach(item => {
            item.addEventListener('click', toggleMenu);
        });

        // Set active nav item
        document.addEventListener('DOMContentLoaded', function() {
            const currentPage = window.location.pathname.split('/').pop();
            const navItems = document.querySelectorAll('.nav-item');
            
            navItems.forEach(item => {
                item.classList.remove('active');
                if (item.getAttribute('href') === currentPage) {
                    item.classList.add('active');
                }
            });

            // Initialize Pie Chart if data exists
            <% if (!categoryStats.isEmpty()) { %>
            initializePieChart();
            <% } %>
        });

        function initializePieChart() {
            const ctx = document.getElementById('pieChart').getContext('2d');
            
            const pieChart = new Chart(ctx, {
                type: 'pie',
                data: {
                    labels: [<%= chartLabels.toString() %>],
                    datasets: [{
                        data: [<%= chartData.toString() %>],
                        backgroundColor: [<%= chartColors.toString() %>],
                        borderWidth: 2,
                        borderColor: document.body.classList.contains('dark-mode') ? '#374151' : '#ffffff',
                        hoverOffset: 15,
                        hoverBorderWidth: 3
                    }]
                },
                options: {
                    responsive: true,
                    maintainAspectRatio: false,
                    plugins: {
                        legend: {
                            display: false
                        },
                        tooltip: {
                            callbacks: {
                                label: function(context) {
                                    const label = context.label || '';
                                    const value = context.raw || 0;
                                    const total = context.dataset.data.reduce((a, b) => a + b, 0);
                                    const percentage = Math.round((value / total) * 100);
                                    return `${label}: ₹${value.toLocaleString()} (${percentage}%)`;
                                }
                            },
                            backgroundColor: document.body.classList.contains('dark-mode') ? 'rgba(45, 49, 57, 0.9)' : 'rgba(0, 0, 0, 0.8)',
                            titleFont: {
                                size: 14,
                                weight: 'bold'
                            },
                            bodyFont: {
                                size: 13
                            },
                            padding: 12,
                            cornerRadius: 8
                        }
                    },
                    animation: {
                        animateScale: true,
                        animateRotate: true,
                        duration: 1000,
                        easing: 'easeOutQuart'
                    },
                    layout: {
                        padding: {
                            top: 20,
                            bottom: 20
                        }
                    }
                }
            });
        }

        function downloadChart() {
            const chartCanvas = document.getElementById('pieChart');
            if (chartCanvas) {
                const link = document.createElement('a');
                link.download = 'spending-chart.png';
                link.href = chartCanvas.toDataURL('image/png');
                link.click();
            } else {
                alert('No chart available to download.');
            }
        }

        function printReport() {
            window.print();
        }

        function logout() {
            if (confirm('Are you sure you want to log out?')) {
                window.location.href = 'logout.jsp';
            }
        }
    </script>
</body>
</html>