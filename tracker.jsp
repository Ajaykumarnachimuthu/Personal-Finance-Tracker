<%@ page import="java.util.*, java.text.*, com.mongodb.*, com.mongodb.client.*, org.bson.*, com.mongodb.client.model.*" %>
<%@ page import="static com.mongodb.client.model.Filters.*" %>
<%@ page import="static com.mongodb.client.model.Updates.*" %>
<%@ page import="static com.mongodb.client.model.Aggregates.*" %>
<%@ page import="static com.mongodb.client.model.Accumulators.*" %>
<%@ page import="static com.mongodb.client.model.Sorts.*" %>
<%@ page import="java.io.*" %>
<%@ page import="org.bson.types.ObjectId" %>
<%@ page import="org.bson.conversions.Bson" %>
<%!
    // Safe number parsing method
    private double parseSafeDouble(String value) throws NumberFormatException {
        if (value == null || value.trim().isEmpty()) {
            throw new NumberFormatException("Empty input");
        }
        String cleanValue = value.trim().replaceAll("\\s+", "");
        if (!cleanValue.matches("^\\d+(\\.\\d{1,2})?$")) {
            throw new NumberFormatException("Invalid number format");
        }
        double result = Double.parseDouble(cleanValue);
        if (result < 0 || result > 10000000) {
            throw new NumberFormatException("Amount out of range");
        }
        return result;
    }

    private boolean isValidString(String input) {
        return input != null && !input.trim().isEmpty() && input.length() <= 255;
    }

    private boolean isValidCategoryName(String name) {
        return name != null && name.trim().length() >= 2 && 
               name.trim().length() <= 50 && 
               name.matches("^[a-zA-Z0-9\\s\\-&]+$");
    }
    
    private String escapeHtml(String input) {
        if (input == null) return "";
        return input.replace("&", "&amp;")
                   .replace("<", "&lt;")
                   .replace(">", "&gt;")
                   .replace("\"", "&quot;")
                   .replace("'", "&#39;");
    }
    
    // MongoDB ObjectId validation
    private boolean isValidObjectId(String id) {
        return id != null && id.matches("^[0-9a-fA-F]{24}$");
    }
%>
<%
    // Check if user is logged in (MongoDB session)
    String loggedInUserId = (String) session.getAttribute("userId");
    if (loggedInUserId == null) {
        response.sendRedirect("login.jsp");
        return;
    }

    // Initialize variables
    double totalIncome = 0;
    double totalExpense = 0;
    double balance = 0;
    double globalLimit = 0;
    String errorMessage = null;
    String userId = loggedInUserId;

    // MongoDB connection - Using the working pattern from your login.jsp
    MongoClient mongoClient = null;
    MongoDatabase database = null;
    MongoCollection<Document> usersCollection = null;
    MongoCollection<Document> incomesCollection = null;
    MongoCollection<Document> expensesCollection = null;
    
<<<<<<< HEAD
    try {
        Properties props = new Properties();
        props.load(getServletContext().getResourceAsStream("/WEB-INF/config.properties"));
        String connectionString = props.getProperty("mongodb.uri", "mongodb://localhost:27017/finance_tracker");
        
        mongoClient = MongoClients.create(connectionString);
=======
    // First, try environment variable (for Render)
    String envMongoUri = System.getenv("MONGODB_URI");
    if (envMongoUri != null && !envMongoUri.trim().isEmpty()) {
        connectionString = envMongoUri;
        out.println("<!-- Using MONGODB_URI from environment -->");
    } else {
    // Fallback to config.properties (for local development)
        try {
            Properties props = new Properties();
            props.load(getServletContext().getResourceAsStream("/WEB-INF/config.properties"));
            connectionString = props.getProperty("mongodb.uri", connectionString);
            out.println("<!-- Using config.properties -->");
        } catch (Exception e) {
            out.println("<!-- Config load error: " + e.getMessage() + " -->");
            errorMessage = "Configuration error: " + e.getMessage();
        }
    }

    try {
        MongoClientSettings settings = MongoClientSettings.builder()
            .applyConnectionString(new ConnectionString(connectionString))
            .applyToSslSettings(builder -> {
                builder.enabled(true);
                builder.invalidHostNameAllowed(true);
            })
            .applyToSocketSettings(builder -> 
                builder.connectTimeout(30, java.util.concurrent.TimeUnit.SECONDS)
            )
            .build();
            
        mongoClient = MongoClients.create(settings);
        mongoClient.listDatabaseNames().first();
>>>>>>> 8f8a6c067bd5cfd05e2a0a5ddcdcf5a40d49de86
        database = mongoClient.getDatabase("finance_tracker");
        usersCollection = database.getCollection("users");
        incomesCollection = database.getCollection("incomes");
        expensesCollection = database.getCollection("expenses");
        
    } catch (Exception e) {
        errorMessage = "Database connection failed: " + e.getMessage();
    }

    // Load data from MongoDB if connected
    if (mongoClient != null && userId != null) {
        try {
            ObjectId userObjectId = new ObjectId(userId);
            
            Document userDoc = usersCollection.find(eq("_id", userObjectId)).first();
            if (userDoc != null) {
                Double limit = userDoc.getDouble("global_limit");
                globalLimit = limit != null ? limit : 0.0;
            }

            // Get total income - FIXED: Proper cursor handling
            AggregateIterable<Document> incomeResult = incomesCollection.aggregate(
                Arrays.asList(
                    match(eq("user_id", userObjectId)),
                    group(null, sum("total", "$amount"))
                )
            );
            
            Document incomeDoc = incomeResult.first();
            if (incomeDoc != null) {
                Double income = incomeDoc.getDouble("total");
                totalIncome = income != null ? income : 0.0;
            }

            // Get total expense - FIXED: Proper cursor handling
            AggregateIterable<Document> expenseResult = expensesCollection.aggregate(
                Arrays.asList(
                    match(eq("user_id", userObjectId)),
                    group(null, sum("total", "$amount"))
                )
            );
            
            Document expenseDoc = expenseResult.first();
            if (expenseDoc != null) {
                Double expense = expenseDoc.getDouble("total");
                totalExpense = expense != null ? expense : 0.0;
            }

            balance = totalIncome - totalExpense;

        } catch (Exception e) {
            errorMessage = "Database error: " + e.getMessage();
        } finally {
            if (mongoClient != null) {
                mongoClient.close();
            }
        }
    }

    // Handle form actions
    String action = request.getParameter("action");
    if (action != null) {
        // Reconnect for form actions
        MongoClient formMongoClient = null;
        try {
            Properties props = new Properties();
            props.load(getServletContext().getResourceAsStream("/WEB-INF/config.properties"));
            String connectionString = props.getProperty("mongodb.uri", "mongodb://localhost:27017/finance_tracker");
            
            formMongoClient = MongoClients.create(connectionString);
            MongoDatabase formDatabase = formMongoClient.getDatabase("finance_tracker");
            MongoCollection<Document> formUsersCollection = formDatabase.getCollection("users");
            MongoCollection<Document> formIncomesCollection = formDatabase.getCollection("incomes");
            
            ObjectId userObjectId = new ObjectId(userId);
            
            // CSRF token validation
            String sessionToken = (String) session.getAttribute("csrfToken");
            String requestToken = request.getParameter("csrfToken");
            
            if (sessionToken == null) {
                sessionToken = java.util.UUID.randomUUID().toString();
                session.setAttribute("csrfToken", sessionToken);
            }
            
            if (requestToken == null || !sessionToken.equals(requestToken)) {
                errorMessage = "Security validation failed. Please try again.";
            } else if ("addIncome".equals(action)) {
                String amountStr = request.getParameter("incomeAmount");
                if (isValidString(amountStr)) {
                    try {
                        double amount = parseSafeDouble(amountStr);
                        Document income = new Document()
                            .append("user_id", userObjectId)
                            .append("amount", amount)
                            .append("income_date", new java.util.Date())
                            .append("created_at", new java.util.Date());
                        formIncomesCollection.insertOne(income);
                        response.sendRedirect("tracker.jsp");
                        return;
                    } catch (NumberFormatException e) {
                        errorMessage = "Invalid amount format. Please enter a valid number.";
                    }
                } else {
                    errorMessage = "Please enter an income amount.";
                }
            }
            else if ("setGlobalLimit".equals(action)) {
                String limitStr = request.getParameter("globalLimit");
                if (isValidString(limitStr)) {
                    try {
                        double newLimit = parseSafeDouble(limitStr);
                        formUsersCollection.updateOne(
                            eq("_id", userObjectId),
                            set("global_limit", newLimit)
                        );
                        response.sendRedirect("tracker.jsp");
                        return;
                    } catch (NumberFormatException e) {
                        errorMessage = "Invalid limit amount. Please enter a valid number.";
                    }
                } else {
                    errorMessage = "Please enter a global limit amount.";
                }
            }
            else if ("clearIncome".equals(action)) {
                formIncomesCollection.deleteMany(eq("user_id", userObjectId));
                response.sendRedirect("tracker.jsp");
                return;
            }
        } catch (Exception e) {
            errorMessage = "Database error: " + e.getMessage();
        } finally {
            if (formMongoClient != null) {
                formMongoClient.close();
            }
        }
    }
    
    DecimalFormat df = new DecimalFormat("#,##0.00");
    double globalPct = globalLimit > 0 ? (totalExpense / globalLimit) * 100.0 : 0.0;
    
    // Generate new CSRF token if not exists
    String csrfToken = (String) session.getAttribute("csrfToken");
    if (csrfToken == null) {
        csrfToken = java.util.UUID.randomUUID().toString();
        session.setAttribute("csrfToken", csrfToken);
    }
%>

<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>Personal Finance Tracker - Dashboard</title>
    
    <link rel="icon" type="image/png" href="icon.png">
    
    <link href="https://cdn.jsdelivr.net/npm/bootstrap@5.3.3/dist/css/bootstrap.min.css" rel="stylesheet">
    <link href="https://cdnjs.cloudflare.com/ajax/libs/font-awesome/6.0.0/css/all.min.css" rel="stylesheet">
    
    <style>
        :root {
            --primary-color: #38bdf8;
            --secondary-color: #0ea5e9;
            --accent-color: #7dd3fc;
            --success-color: #4facfe;
            --warning-color: #43e97b;
            --danger-color: #fa709a;
            --heading-gradient: linear-gradient(135deg, #38bdf8 0%, #0ea5e9 100%);
            --light-bg: #f8f9fa;
            --dark-bg: #1a1d23;
            --dark-card: #2d3139;
            --dark-text: #e9ecef;
            --card-shadow: 0 8px 25px rgba(0,0,0,0.1);
            --hover-shadow: 0 12px 35px rgba(0,0,0,0.15);
            --dark-shadow: 0 8px 25px rgba(0,0,0,0.3);
        }
        
        /* Dark Mode Styles */
        body.dark-mode {
            background: var(--dark-bg);
            color: var(--dark-text);
        }
        
        body.dark-mode .app-header {
            background: linear-gradient(135deg, #1e3a8a 0%, #1e40af 100%);
        }
        
        body.dark-mode .metric-card,
        body.dark-mode .chart-container,
        body.dark-mode .stat-card {
            background: var(--dark-card);
            color: var(--dark-text);
            box-shadow: var(--dark-shadow);
        }
        
        body.dark-mode .form-control {
            background: #3a3f47;
            border-color: #4b5563;
            color: var(--dark-text);
        }
        
        body.dark-mode .form-control:focus {
            background: #3a3f47;
            border-color: var(--primary-color);
            color: var(--dark-text);
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
        
        body.dark-mode .nav-item:hover {
            background: #374151;
            color: var(--primary-color);
        }
        
        * {
            margin: 0;
            padding: 0;
            box-sizing: border-box;
            transition: background-color 0.3s ease, color 0.3s ease;
        }
        
        body {
            background: var(--light-bg);
            font-family: 'Segoe UI', Tahoma, Geneva, Verdana, sans-serif;
            color: #333;
            line-height: 1.6;
            padding-bottom: 80px;
            min-height: 100vh;
        }
        
        /* Animated Background */
        .animated-bg {
            position: fixed;
            top: 0;
            left: 0;
            width: 100%;
            height: 100%;
            z-index: -1;
            opacity: 0.03;
        }
        
        .floating-shape {
            position: absolute;
            border-radius: 50%;
            background: var(--primary-color);
            animation: float 20s infinite linear;
        }
        
        .shape-1 {
            width: 100px;
            height: 100px;
            top: 10%;
            left: 10%;
            animation-duration: 25s;
        }
        
        .shape-2 {
            width: 150px;
            height: 150px;
            top: 70%;
            left: 80%;
            animation-duration: 30s;
        }
        
        .shape-3 {
            width: 80px;
            height: 80px;
            top: 20%;
            left: 85%;
            animation-duration: 20s;
        }
        
        @keyframes float {
            0% { transform: translateY(0) rotate(0deg); }
            50% { transform: translateY(-20px) rotate(180deg); }
            100% { transform: translateY(0) rotate(360deg); }
        }
        
        /* Header Styles */
        .app-header {
            background: var(--heading-gradient);
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
        
        @media (max-width: 768px) {
            .app-title {
                font-size: 1.5rem;
                margin: 0 50px;
            }
        }
        
        @media (max-width: 480px) {
            .app-title {
                font-size: 1.3rem;
                margin: 0 45px;
            }
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
        
        /* Metrics Grid */
        .metrics-grid {
            display: grid;
            grid-template-columns: 1fr 1fr;
            grid-template-rows: auto auto;
            gap: 1rem;
            margin-bottom: 3rem;
            padding: 0 1rem;
        }
        
        @media (min-width: 768px) {
            .metrics-grid {
                grid-template-columns: repeat(4, 1fr);
                grid-template-rows: auto;
                gap: 1.5rem;
                padding: 0;
            }
        }
        
        .metric-card {
            background: white;
            padding: 1.5rem;
            border-radius: 16px;
            box-shadow: var(--card-shadow);
            border: 1px solid #e9ecef;
            transition: all 0.3s ease;
            position: relative;
            overflow: hidden;
            display: flex;
            flex-direction: column;
            align-items: center;
            text-align: center;
        }
        
        .metric-card:hover {
            transform: translateY(-5px);
            box-shadow: var(--hover-shadow);
            border-color: var(--primary-color);
        }
        
        .metric-icon {
            font-size: 2rem;
            color: var(--primary-color);
            margin-bottom: 1rem;
        }
        
        .metric-label {
            font-size: 0.8rem;
            font-weight: 600;
            color: #6c757d;
            text-transform: uppercase;
            letter-spacing: 0.5px;
            margin-bottom: 0.5rem;
        }
        
        body.dark-mode .metric-label {
            color: #9ca3af;
        }
        
        .metric-value {
            font-size: 1.75rem;
            font-weight: 700;
            color: var(--primary-color);
            margin-bottom: 0.5rem;
        }
        
        .metric-extra {
            font-size: 0.8rem;
            color: #6c757d;
            margin-bottom: 1rem;
        }
        
        body.dark-mode .metric-extra {
            color: #9ca3af;
        }
        
        .progress {
            height: 8px;
            border-radius: 4px;
            margin: 0.5rem 0;
            width: 100%;
        }
        
        .btn {
            border-radius: 8px;
            font-weight: 600;
            transition: all 0.3s ease;
        }
        
        .btn-primary {
            background: var(--primary-color);
            border-color: var(--primary-color);
        }
        
        .btn-primary:hover {
            background: var(--secondary-color);
            border-color: var(--secondary-color);
            transform: translateY(-1px);
        }
        
        .alert {
            border-radius: 12px;
            border: none;
            margin-bottom: 1rem;
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
        
        @media (max-width: 576px) {
            .app-title {
                font-size: 1.8rem;
            }
            
            .metrics-grid {
                gap: 0.75rem;
                padding: 0 0.5rem;
            }
            
            .metric-card {
                padding: 1rem;
            }
            
            .metric-value {
                font-size: 1.5rem;
            }
        }
    </style>
</head>
<body>
    <!-- Animated Background -->
    <div class="animated-bg">
        <div class="floating-shape shape-1"></div>
        <div class="floating-shape shape-2"></div>
        <div class="floating-shape shape-3"></div>
    </div>

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
                <h1 class="app-title">Personal Finance Tracker</h1>

                <!-- Theme Toggle -->
                <div class="theme-toggle" id="themeToggle">
                    <i class="fas fa-moon"></i>
                </div>
            </div>
        </div>
    </div>

    <!-- Sidebar Menu -->
    <div class="sidebar-menu" id="sidebarMenu">
        <button class="menu-item" onclick="showColorGuide()">
            <i class="fas fa-palette"></i>
            <span>Color Guide</span>
        </button>
        <button class="menu-item" onclick="resetData()">
            <i class="fas fa-redo"></i>
            <span>Reset Data</span>
        </button>
        <button class="menu-item" onclick="clearIncome()">
            <i class="fas fa-trash"></i>
            <span>Clear Income</span>
        </button>
        <button class="menu-item" onclick="exportData()">
            <i class="fas fa-download"></i>
            <span>Export Data</span>
        </button>
        <button class="menu-item" onclick="printReport()">
            <i class="fas fa-print"></i>
            <span>Print Report</span>
        </button>
        <button class="menu-item" onclick="showQuickStats()">
            <i class="fas fa-chart-bar"></i>
            <span>Quick Stats</span>
        </button>
        <button class="menu-item" onclick="openCalculator()">
            <i class="fas fa-calculator"></i>
            <span>Calculator</span>
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

    <div class="container mt-4">
        <!-- Metrics Grid -->
        <div class="metrics-grid">
            <!-- Total Income -->
            <div class="metric-card">
                <div class="metric-icon"><i class="fas fa-money-bill-wave"></i></div>
                <div class="metric-label">TOTAL INCOME</div>
                <div class="metric-value">&#8377;<%= df.format(totalIncome) %></div>
                <form method="post" class="mt-3 w-100">
                    <input type="hidden" name="action" value="addIncome"/>
                    <input type="hidden" name="csrfToken" value="<%= csrfToken %>"/>
                    <div class="input-group input-group-sm">
                        <input type="number" step="0.01" min="0" max="1000000" name="incomeAmount" 
                               class="form-control" placeholder="Amount" required>
                        <button class="btn btn-primary btn-sm">
                            <i class="fas fa-plus me-1"></i>Add
                        </button>
                    </div>
                </form>
            </div>

            <!-- Spending -->
            <div class="metric-card">
                <div class="metric-icon"><i class="fas fa-shopping-cart"></i></div>
                <div class="metric-label">SPENDING</div>
                <div class="metric-value">&#8377;<%= df.format(totalExpense) %></div>
                <div class="metric-extra">Across all categories</div>
            </div>

            <!-- Balance -->
            <div class="metric-card">
                <div class="metric-icon"><i class="fas fa-balance-scale"></i></div>
                <div class="metric-label">BALANCE</div>
                <div class="metric-value <%= balance >= 0 ? "text-success" : "text-danger" %>">
                    &#8377;<%= df.format(balance) %>
                </div>
                <div class="metric-extra"><%= balance >= 0 ? "Under budget" : "Over budget" %></div>
            </div>

            <!-- Global Limit -->
            <div class="metric-card">
                <div class="metric-icon"><i class="fas fa-bullseye"></i></div>
                <div class="metric-label">GLOBAL LIMIT</div>
                <div class="metric-value">&#8377;<%= df.format(globalLimit) %></div>
                <form method="post" class="mt-3 w-100">
                    <input type="hidden" name="action" value="setGlobalLimit"/>
                    <input type="hidden" name="csrfToken" value="<%= csrfToken %>"/>
                    <div class="input-group input-group-sm">
                        <input type="number" step="0.01" min="0" max="10000000" name="globalLimit" 
                               class="form-control" placeholder="Set limit" value="<%= globalLimit %>" required>
                        <button class="btn btn-outline-primary btn-sm">
                            <i class="fas fa-save me-1"></i>Save
                        </button>
                    </div>
                </form>
                <div class="progress">
                    <div class="progress-bar <%= globalPct >= 100 ? "bg-danger" : (globalPct >= 80 ? "bg-warning" : "bg-success") %>" 
                         style="width: <%= Math.min(globalPct, 100) %>%"
                         role="progressbar" 
                         aria-valuenow="<%= Math.min(globalPct, 100) %>" 
                         aria-valuemin="0" 
                         aria-valuemax="100">
                    </div>
                </div>
                <div class="metric-extra"><%= String.format("%.1f", Math.min(globalPct, 100)) %>% of limit used</div>
            </div>
        </div>
    </div>

    <!-- Bottom Navigation -->
    <nav class="bottom-nav">
        <div class="container">
            <div class="nav-grid">
                <a href="tracker.jsp" class="nav-item active">
                    <i class="fas fa-home nav-icon"></i>
                    <span class="nav-label">Home</span>
                </a>
                <a href="categories.jsp" class="nav-item">
                    <i class="fas fa-folder nav-icon"></i>
                    <span class="nav-label">Categories</span>
                </a>
                <a href="statistics.jsp" class="nav-item">
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
        
        // Check for saved theme preference or default to light
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

        // Menu Functions
        function showColorGuide() {
            alert('Color Guide:\n\n• Green: Good usage (under 80%)\n• Yellow: Warning (80-99%)\n• Red: Over limit (100%+)');
        }

        function resetData() {
            if (confirm('Are you sure you want to reset all data? This cannot be undone.')) {
                // Implement reset functionality
                alert('Reset functionality would be implemented here.');
            }
        }

        function clearIncome() {
            if (confirm('Are you sure you want to clear all income records?')) {
                const form = document.createElement('form');
                form.method = 'POST';
                form.action = window.location.href;
                
                const actionInput = document.createElement('input');
                actionInput.type = 'hidden';
                actionInput.name = 'action';
                actionInput.value = 'clearIncome';
                
                const csrfInput = document.createElement('input');
                csrfInput.type = 'hidden';
                csrfInput.name = 'csrfToken';
                csrfInput.value = '<%= csrfToken %>';
                
                form.appendChild(actionInput);
                form.appendChild(csrfInput);
                document.body.appendChild(form);
                
                form.submit();
            }
        }

        function openCalculator() {
            window.location.href = 'calculator.jsp';
        }

        function logout() {
            if (confirm('Are you sure you want to log out?')) {
                window.location.href = 'logout.jsp';
            }
        }

        function printReport() {
            window.print();
        }

        function exportData() {
            alert('Export functionality would be implemented here.');
        }

        function showQuickStats() {
            alert('Quick stats functionality would be implemented here.');
        }

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
        });
    </script>
</body>
</html>
