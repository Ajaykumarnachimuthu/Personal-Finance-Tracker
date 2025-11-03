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
    // Check if user is logged in
    String loggedInUserId = (String) session.getAttribute("userId");
    if (loggedInUserId == null) {
        response.sendRedirect("login.jsp");
        return;
    }

    // Initialize variables
    List<Document> categories = new ArrayList<>();
    Map<String, List<Document>> expensesByCategory = new HashMap<>();
    String errorMessage = null;
    String userId = loggedInUserId;

    // MongoDB connection
    MongoClient mongoClient = null;
    MongoDatabase database = null;
    MongoCollection<Document> categoriesCollection = null;
    MongoCollection<Document> expensesCollection = null;
    
    Properties props = new Properties();
    String connectionString = "mongodb://localhost:27017/finance_tracker";
    boolean dbConnected = false;
    
    // First, try environment variable (for Render)
    String envMongoUri = System.getenv("MONGODB_URI");
    if (envMongoUri != null && !envMongoUri.trim().isEmpty()) {
        connectionString = envMongoUri;
    } else {
        // Fallback to config.properties (for local development)
        try {
            props.load(getServletContext().getResourceAsStream("/WEB-INF/config.properties"));
            connectionString = props.getProperty("mongodb.uri", connectionString);
        } catch (Exception e) {
            errorMessage = "Configuration error: " + e.getMessage();
        }
    }

    try {
        MongoClientSettings settings = MongoClientSettings.builder()
            .applyConnectionString(new ConnectionString(connectionString))
            .applyToSocketSettings(builder -> 
                builder.connectTimeout(30, java.util.concurrent.TimeUnit.SECONDS)
            )
            .build();
            
        mongoClient = MongoClients.create(settings);
        database = mongoClient.getDatabase("finance_tracker");
        categoriesCollection = database.getCollection("categories");
        expensesCollection = database.getCollection("expenses");
        
        dbConnected = true;
        
    } catch (Exception e) {
        errorMessage = "Database connection failed. Running in demo mode.";
    }

    // Demo data for when connection fails
    if (!dbConnected) {
        categories.add(new Document("_id", new ObjectId())
            .append("name", "Food & Dining")
            .append("color", "#60A5FA")
            .append("limit_amount", 500.0)
            .append("total", 325.50));
            
        categories.add(new Document("_id", new ObjectId())
            .append("name", "Transportation")
            .append("color", "#34D399")
            .append("limit_amount", 300.0)
            .append("total", 180.25));
            
        categories.add(new Document("_id", new ObjectId())
            .append("name", "Entertainment")
            .append("color", "#FBBF24")
            .append("limit_amount", 200.0)
            .append("total", 75.80));
    }

    // Load data from MongoDB if connected
    if (dbConnected && mongoClient != null && userId != null) {
        try {
            ObjectId userObjectId = new ObjectId(userId);

            // Get categories for this user
            FindIterable<Document> categoriesCursor = categoriesCollection.find(eq("user_id", userObjectId));
            String[] defaultColors = {"#60A5FA", "#34D399", "#FBBF24", "#F87171", "#A78BFA", "#38BDF8", "#A3E635", "#FB923C"};
            int colorIndex = 0;
            
            // Proper cursor iteration
            MongoCursor<Document> cursor = categoriesCursor.iterator();
            while (cursor.hasNext()) {
                Document category = cursor.next();
                if (category.getString("color") == null) {
                    category.put("color", defaultColors[colorIndex % defaultColors.length]);
                }
                if (category.getDouble("limit_amount") == null) {
                    category.put("limit_amount", 0.0);
                }
                categories.add(category);
                colorIndex++;
            }
            cursor.close();

            // Get expenses for all categories
            if (!categories.isEmpty()) {
                List<ObjectId> categoryIds = new ArrayList<>();
                for (Document category : categories) {
                    categoryIds.add(category.getObjectId("_id"));
                }
                
                // Calculate category totals
                for (Document category : categories) {
                    ObjectId catId = category.getObjectId("_id");
                    
                    List<? extends Bson> catExpensePipeline = Arrays.asList(
                        match(eq("category_id", catId)),
                        group(null, sum("total", "$amount"))
                    );
                    
                    AggregateIterable<Document> catExpenseResult = expensesCollection.aggregate(catExpensePipeline);
                    Document catTotalDoc = catExpenseResult.first();
                    double catTotal = 0.0;
                    if (catTotalDoc != null) {
                        Double total = catTotalDoc.getDouble("total");
                        catTotal = total != null ? total : 0.0;
                    }
                    
                    category.put("total", catTotal);
                }
                
                // Get individual expenses
                FindIterable<Document> expensesCursor = expensesCollection.find(in("category_id", categoryIds))
                    .sort(descending("spent_at"));
                
                // Proper cursor iteration
                MongoCursor<Document> expensesIterator = expensesCursor.iterator();
                while (expensesIterator.hasNext()) {
                    Document expense = expensesIterator.next();
                    ObjectId catId = expense.getObjectId("category_id");
                    String catIdStr = catId.toString();
                    
                    if (!expensesByCategory.containsKey(catIdStr)) {
                        expensesByCategory.put(catIdStr, new ArrayList<>());
                    }
                    expensesByCategory.get(catIdStr).add(expense);
                }
                expensesIterator.close();
            }

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
        if (dbConnected && userId != null) {
            MongoClient formMongoClient = null;
            try {
                formMongoClient = MongoClients.create(connectionString);
                MongoDatabase formDatabase = formMongoClient.getDatabase("finance_tracker");
                MongoCollection<Document> formCategoriesCollection = formDatabase.getCollection("categories");
                MongoCollection<Document> formExpensesCollection = formDatabase.getCollection("expenses");
                
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
                } else if ("addCategory".equals(action)) {
                    String catName = request.getParameter("newCategory");
                    if (isValidCategoryName(catName)) {
                        Document existingCategory = formCategoriesCollection.find(
                            and(eq("user_id", userObjectId), eq("name", catName.trim()))
                        ).first();
                        
                        if (existingCategory != null) {
                            errorMessage = "Category '" + catName + "' already exists.";
                        } else {
                            String[] colors = {"#60A5FA", "#34D399", "#FBBF24", "#F87171", "#A78BFA", "#38BDF8", "#A3E635", "#FB923C"};
                            Document category = new Document()
                                .append("user_id", userObjectId)
                                .append("name", catName.trim())
                                .append("color", colors[categories.size() % colors.length])
                                .append("limit_amount", 0.0)
                                .append("created_at", new java.util.Date());
                            formCategoriesCollection.insertOne(category);
                            response.sendRedirect("categories.jsp");
                            return;
                        }
                    } else {
                        errorMessage = "Category name must be 2-50 characters long and contain only letters, numbers, spaces, hyphens, and ampersands.";
                    }
                }
                else if ("deleteCategory".equals(action)) {
                    String catIdStr = request.getParameter("categoryId");
                    if (isValidObjectId(catIdStr)) {
                        ObjectId catId = new ObjectId(catIdStr);
                        formExpensesCollection.deleteMany(eq("category_id", catId));
                        formCategoriesCollection.deleteOne(
                            and(eq("_id", catId), eq("user_id", userObjectId))
                        );
                        response.sendRedirect("categories.jsp");
                        return;
                    } else {
                        errorMessage = "Invalid category ID.";
                    }
                }
                else if ("setCatLimit".equals(action)) {
                    String catIdStr = request.getParameter("categoryId");
                    String limitStr = request.getParameter("limit");
                    if (isValidObjectId(catIdStr) && isValidString(limitStr)) {
                        try {
                            ObjectId catId = new ObjectId(catIdStr);
                            double limit = parseSafeDouble(limitStr);
                            formCategoriesCollection.updateOne(
                                and(eq("_id", catId), eq("user_id", userObjectId)),
                                set("limit_amount", limit)
                            );
                            response.sendRedirect("categories.jsp");
                            return;
                        } catch (NumberFormatException e) {
                            errorMessage = "Invalid limit amount. Please enter a valid number.";
                        }
                    } else {
                        errorMessage = "Please enter a valid category limit.";
                    }
                }
                else if ("addExpense".equals(action)) {
                    String catIdStr = request.getParameter("categoryId");
                    String amountStr = request.getParameter("amount");
                    String item = request.getParameter("item");
                    if (isValidObjectId(catIdStr) && isValidString(amountStr) && isValidString(item)) {
                        try {
                            ObjectId catId = new ObjectId(catIdStr);
                            double amount = parseSafeDouble(amountStr);
                            Document expense = new Document()
                                .append("category_id", catId)
                                .append("amount", amount)
                                .append("item", item.trim())
                                .append("spent_at", new java.util.Date())
                                .append("created_at", new java.util.Date());
                            formExpensesCollection.insertOne(expense);
                            response.sendRedirect("categories.jsp");
                            return;
                        } catch (NumberFormatException e) {
                            errorMessage = "Invalid amount format. Please enter a valid number.";
                        }
                    } else {
                        errorMessage = "Please fill in all expense fields.";
                    }
                }
                else if ("deleteExpense".equals(action)) {
                    String expIdStr = request.getParameter("expenseId");
                    if (isValidObjectId(expIdStr)) {
                        ObjectId expId = new ObjectId(expIdStr);
                        formExpensesCollection.deleteOne(eq("_id", expId));
                        response.sendRedirect("categories.jsp");
                        return;
                    } else {
                        errorMessage = "Invalid expense ID.";
                    }
                }
                else if ("updateCategoryColor".equals(action)) {
                    String catIdStr = request.getParameter("categoryId");
                    String newColor = request.getParameter("color");
                    if (isValidObjectId(catIdStr) && newColor != null && newColor.matches("^#[0-9A-Fa-f]{6}$")) {
                        ObjectId catId = new ObjectId(catIdStr);
                        formCategoriesCollection.updateOne(
                            and(eq("_id", catId), eq("user_id", userObjectId)),
                            set("color", newColor)
                        );
                        response.sendRedirect("categories.jsp");
                        return;
                    } else {
                        errorMessage = "Please select a valid color.";
                    }
                }
            } catch (Exception e) {
                errorMessage = "Database error: " + e.getMessage();
            } finally {
                if (formMongoClient != null) {
                    formMongoClient.close();
                }
            }
        } else {
            errorMessage = "Database not available. Please try again later.";
        }
    }
    
    DecimalFormat df = new DecimalFormat("#,##0.00");
    SimpleDateFormat dateFormat = new SimpleDateFormat("dd MMM yyyy");
    
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
    <title>Personal Finance Tracker - Categories</title>
    
    <link rel="icon" type="image/png" href="icon.png">
    <link href="https://cdn.jsdelivr.net/npm/bootstrap@5.3.3/dist/css/bootstrap.min.css" rel="stylesheet">
    <link href="https://cdnjs.cloudflare.com/ajax/libs/font-awesome/6.0.0/css/all.min.css" rel="stylesheet">
    
    <style>
        :root {
            --primary-color: #38bdf8;
            --secondary-color: #0ea5e9;
            --light-bg: #f8f9fa;
            --dark-bg: #1a1d23;
            --dark-card: #2d3139;
            --dark-header: #374151;
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
        
        body.dark-mode .modal-content,
        body.dark-mode .card {
            background: var(--dark-card);
            color: var(--dark-text);
        }

        /* Delete Modal Dark Mode Styles - FIXED */
        body.dark-mode #deleteCategoryModal .modal-content {
            background: var(--dark-card);
            color: var(--dark-text);
            border: 1px solid #374151;
        }

        body.dark-mode #deleteCategoryModal .modal-header {
            border-bottom: 1px solid #374151;
            background: var(--dark-header);
            color: var(--dark-text);
        }

        body.dark-mode #deleteCategoryModal .modal-footer {
            border-top: 1px solid #374151;
            background: var(--dark-header);
        }

        body.dark-mode #deleteCategoryModal .btn-close {
            filter: invert(1) grayscale(100%) brightness(200%);
        }

        body.dark-mode #deleteCategoryModal .text-danger {
            color: #f87171 !important;
        }

        body.dark-mode #deleteCategoryModal .btn-secondary {
            background: #4b5563;
            border-color: #4b5563;
            color: white;
        }

        body.dark-mode #deleteCategoryModal .btn-secondary:hover {
            background: #6b7280;
            border-color: #6b7280;
        }

        body.dark-mode #deleteCategoryModal .btn-danger {
            background: #dc2626;
            border-color: #dc2626;
        }

        body.dark-mode #deleteCategoryModal .btn-danger:hover {
            background: #b91c1c;
            border-color: #b91c1c;
        }

        /* Selection Modal Dark Mode */
        body.dark-mode #deleteSelectionModal .modal-content {
            background: var(--dark-card);
            color: var(--dark-text);
            border: 1px solid #374151;
        }

        body.dark-mode #deleteSelectionModal .modal-header {
            border-bottom: 1px solid #374151;
            background: var(--dark-header);
            color: var(--dark-text);
        }

        body.dark-mode #deleteSelectionModal .modal-footer {
            border-top: 1px solid #374151;
            background: var(--dark-header);
        }

        body.dark-mode #deleteSelectionModal .btn-close {
            filter: invert(1) grayscale(100%) brightness(200%);
        }

        /* Enhanced Dark Mode Category Tiles */
        body.dark-mode .category-tile {
            background: linear-gradient(135deg, var(--color) 0%, var(--color) 100%);
            color: white;
            position: relative;
            box-shadow: 0 4px 6px rgba(0,0,0,0.3);
        }

        /* Text readability overlay */
        body.dark-mode .category-tile::before {
            content: '';
            position: absolute;
            top: 0;
            left: 0;
            right: 0;
            bottom: 0;
            background: rgba(0, 0, 0, 0.3);
            border-radius: 12px;
            z-index: 1;
        }

        body.dark-mode .category-tile > * {
            position: relative;
            z-index: 2;
        }

        /* Improve text contrast for specific light colors */
        body.dark-mode .category-tile[style*="color: #FBBF24"],
        body.dark-mode .category-tile[style*="color: #FACC15"],
        body.dark-mode .category-tile[style*="color: #A3E635"],
        body.dark-mode .category-tile[style*="color: #4ADE80"],
        body.dark-mode .category-tile[style*="color: #34D399"],
        body.dark-mode .category-tile[style*="color: #22D3EE"],
        body.dark-mode .category-tile[style*="color: #38BDF8"],
        body.dark-mode .category-tile[style*="color: #60A5FA"],
        body.dark-mode .category-tile[style*="color: #A78BFA"],
        body.dark-mode .category-tile[style*="color: #C084FC"],
        body.dark-mode .category-tile[style*="color: #FB923C"] {
            color: #1a1d23 !important;
            font-weight: 700;
        }

        /* Lighter overlay for light background colors */
        body.dark-mode .category-tile[style*="color: #FBBF24"]::before,
        body.dark-mode .category-tile[style*="color: #FACC15"]::before,
        body.dark-mode .category-tile[style*="color: #A3E635"]::before,
        body.dark-mode .category-tile[style*="color: #4ADE80"]::before,
        body.dark-mode .category-tile[style*="color: #34D399"]::before,
        body.dark-mode .category-tile[style*="color: #22D3EE"]::before,
        body.dark-mode .category-tile[style*="color: #38BDF8"]::before,
        body.dark-mode .category-tile[style*="color: #60A5FA"]::before,
        body.dark-mode .category-tile[style*="color: #A78BFA"]::before,
        body.dark-mode .category-tile[style*="color: #C084FC"]::before,
        body.dark-mode .category-tile[style*="color: #FB923C"]::before {
            background: rgba(255, 255, 255, 0.15);
        }
        
        body.dark-mode .add-category-btn {
            background: #374151;
            border-color: #4b5563;
            color: #9ca3af;
        }
        
        body.dark-mode .add-category-btn:hover {
            background: #4b5563;
            border-color: var(--primary-color);
            color: var(--primary-color);
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
        
        body.dark-mode .list-group-item {
            background: var(--dark-card);
            border-color: #374151;
            color: var(--dark-text);
        }
        
        body.dark-mode .empty-state {
            color: #9ca3af;
        }
        
        /* Base Styles */
        body {
            background: var(--light-bg);
            font-family: 'Segoe UI', Tahoma, Geneva, Verdana, sans-serif;
            padding-bottom: 80px;
            min-height: 100vh;
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
        
        /* Categories Section */
        .categories-section {
            margin-bottom: 3rem;
            padding: 0 1rem;
        }
        
        @media (min-width: 768px) {
            .categories-section {
                padding: 0;
            }
        }
        
        .section-title {
            font-weight: 700;
            color: var(--primary-color);
            margin-bottom: 1.5rem;
            font-size: 1.5rem;
            text-align: center;
        }
        
        .categories-grid {
            display: grid;
            grid-template-columns: repeat(auto-fill, minmax(280px, 1fr));
            gap: 1rem;
        }
        
        @media (max-width: 768px) {
            .categories-grid {
                grid-template-columns: 1fr;
                gap: 0.75rem;
            }
        }
        
        /* Full color category tiles */
        .category-tile {
            background: white;
            padding: 1.2rem;
            border-radius: 12px;
            box-shadow: 0 4px 6px rgba(0,0,0,0.07);
            background: linear-gradient(135deg, var(--color) 0%, var(--color) 100%);
            color: white;
            cursor: pointer;
            transition: all 0.2s;
            position: relative;
            font-weight: 600;
            display: flex;
            align-items: center;
            justify-content: center;
            text-align: center;
            min-height: 80px;
            border: none;
            font-size: 0.95rem;
        }
        
        .category-tile:hover {
            transform: translateY(-2px);
            box-shadow: 0 6px 12px rgba(0,0,0,0.1);
            filter: brightness(1.1);
        }
        
        .add-category-btn {
            background: #f8f9fa;
            border: 2px dashed #dee2e6;
            padding: 1.2rem;
            border-radius: 12px;
            cursor: pointer;
            transition: all 0.2s;
            color: #6c757d;
            font-weight: 600;
            display: flex;
            align-items: center;
            justify-content: center;
            min-height: 80px;
            text-decoration: none;
            font-size: 0.95rem;
        }
        
        .add-category-btn:hover {
            background: #e9ecef;
            border-color: var(--primary-color);
            color: var(--primary-color);
            transform: translateY(-2px);
            text-decoration: none;
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
        
        /* Color Picker Styles */
        .color-picker-dropdown {
            position: relative;
            margin-bottom: 1.5rem;
        }
        
        .color-dropdown-btn {
            width: 100%;
            padding: 0.75rem;
            border: 1px solid #dee2e6;
            border-radius: 8px;
            background: white;
            display: flex;
            justify-content: space-between;
            align-items: center;
            cursor: pointer;
            transition: all 0.3s ease;
        }
        
        .color-dropdown-btn:hover {
            border-color: var(--primary-color);
        }
        
        .color-dropdown-content {
            display: none;
            position: absolute;
            background: white;
            border: 1px solid #dee2e6;
            border-radius: 8px;
            padding: 1rem;
            width: 100%;
            z-index: 1000;
            box-shadow: 0 4px 12px rgba(0,0,0,0.1);
        }
        
        body.dark-mode .color-dropdown-content {
            background: var(--dark-card);
            border-color: #374151;
        }
        
        .color-dropdown-content.show {
            display: block;
        }
        
        .color-options-grid {
            display: grid;
            grid-template-columns: repeat(6, 1fr);
            gap: 0.5rem;
            margin-bottom: 1rem;
        }
        
        .color-option {
            width: 30px;
            height: 30px;
            border-radius: 6px;
            cursor: pointer;
            border: 2px solid transparent;
            transition: all 0.2s;
        }
        
        .color-option:hover {
            transform: scale(1.1);
        }
        
        .color-option.selected {
            border-color: #333;
            transform: scale(1.1);
        }
        
        body.dark-mode .color-option.selected {
            border-color: #fff;
        }
        
        .color-preview {
            display: inline-block;
            width: 20px;
            height: 20px;
            border-radius: 4px;
            margin: 0 0.5rem;
            border: 1px solid #dee2e6;
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
        
        .empty-state {
            text-align: center;
            padding: 3rem 1rem;
            color: #6c757d;
        }
        
        body.dark-mode .empty-state {
            color: #9ca3af;
        }
        
        .empty-state i {
            font-size: 3rem;
            margin-bottom: 1rem;
        }
        
        @media (max-width: 576px) {
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
                <h1 class="app-title">Categories</h1>

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
        <button class="menu-item" onclick="window.location.href='statistics.jsp'">
            <i class="fas fa-chart-pie"></i>
            <span>Statistics</span>
        </button>
        <button class="menu-item" onclick="window.location.href='recent.jsp'">
            <i class="fas fa-history"></i>
            <span>Recent</span>
        </button>
        <button class="menu-item" onclick="showDeleteCategorySelection()">
            <i class="fas fa-trash"></i>
            <span>Delete Categories</span>
        </button>
        <button class="menu-item" onclick="showColorGuide()">
            <i class="fas fa-palette"></i>
            <span>Color Guide</span>
        </button>
        <button class="menu-item" onclick="exportCategories()">
            <i class="fas fa-download"></i>
            <span>Export Data</span>
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
        <!-- Categories Section -->
        <div class="categories-section">
            <div class="categories-grid">
                <% for (Document category : categories) { 
                    String catId = category.getObjectId("_id").toString();
                    String catName = escapeHtml(category.getString("name"));
                    String catColor = category.getString("color");
                    double catLimit = category.getDouble("limit_amount") != null ? category.getDouble("limit_amount") : 0.0;
                    double catTotal = category.getDouble("total") != null ? category.getDouble("total") : 0.0;
                    double catPct = catLimit > 0 ? (catTotal / catLimit) * 100.0 : 0.0;
                %>
                <div class="category-tile" style="--color: <%= catColor %>;"
                     onclick="openCategoryModal('<%= catId %>')"
                     aria-label="View <%= catName %> expenses">
                    <%= catName %>
                </div>
                <% } %>

                <a href="#" class="add-category-btn" data-bs-toggle="modal" data-bs-target="#addCategoryModal"
                        aria-label="Add new category">
                    <i class="fas fa-plus me-2"></i>ADD CATEGORY
                </a>
            </div>
        </div>
    </div>

    <!-- Category Detail Modals -->
    <% for (Document category : categories) { 
        String catId = category.getObjectId("_id").toString();
        String catName = escapeHtml(category.getString("name"));
        String catColor = category.getString("color");
        double catLimit = category.getDouble("limit_amount") != null ? category.getDouble("limit_amount") : 0.0;
        double catTotal = category.getDouble("total") != null ? category.getDouble("total") : 0.0;
        double catPct = catLimit > 0 ? (catTotal / catLimit) * 100.0 : 0.0;
        
        List<Document> categoryExpenses = expensesByCategory.get(catId);
    %>
    <div class="modal fade" id="modal_<%= catId %>" tabindex="-1" aria-labelledby="modalLabel_<%= catId %>" aria-hidden="true">
        <div class="modal-dialog modal-lg modal-dialog-centered">
            <div class="modal-content">
                <div class="modal-header" style="background: <%= catColor %>; color: white;">
                    <h5 class="modal-title" id="modalLabel_<%= catId %>">
                        <i class="fas fa-folder me-2"></i>
                        <%= catName %>
                    </h5>
                    <button type="button" class="btn-close btn-close-white" data-bs-dismiss="modal" aria-label="Close"></button>
                </div>
                <div class="modal-body">
                    <!-- Category Stats -->
                    <div class="row mb-4">
                        <div class="col-md-6">
                            <div class="card">
                                <div class="card-body">
                                    <h6 class="card-title">Spent</h6>
                                    <h3 class="text-primary">&#8377;<%= df.format(catTotal) %></h3>
                                </div>
                            </div>
                        </div>
                        <div class="col-md-6">
                            <div class="card">
                                <div class="card-body">
                                    <h6 class="card-title">Limit</h6>
                                    <h3 class="text-info">&#8377;<%= df.format(catLimit) %></h3>
                                </div>
                            </div>
                        </div>
                    </div>
                    
                    <!-- Progress Bar -->
                    <div class="mb-4">
                        <div class="d-flex justify-content-between mb-2">
                            <span>Usage</span>
                            <span><%= String.format("%.1f", Math.min(catPct, 100)) %>%</span>
                        </div>
                        <div class="progress" style="height: 10px;">
                            <div class="progress-bar <%= catPct >= 100 ? "bg-danger" : (catPct >= 80 ? "bg-warning" : "bg-success") %>" 
                                 style="width: <%= Math.min(catPct, 100) %>%">
                            </div>
                        </div>
                    </div>
                    
                    <!-- Update Limit Form -->
                    <form method="post" class="mb-4">
                        <input type="hidden" name="action" value="setCatLimit"/>
                        <input type="hidden" name="categoryId" value="<%= catId %>"/>
                        <input type="hidden" name="csrfToken" value="<%= csrfToken %>"/>
                        <div class="input-group">
                            <input type="number" step="0.01" min="0" max="1000000" name="limit" 
                                   class="form-control" placeholder="Set category limit" value="<%= catLimit %>" required>
                            <button class="btn btn-primary">
                                <i class="fas fa-save me-1"></i>Update Limit
                            </button>
                        </div>
                    </form>
                    
                    <!-- Color Picker -->
                    <div class="color-picker-dropdown mb-4">
                        <div class="color-dropdown-btn" onclick="toggleColorDropdown('<%= catId %>')">
                            <span>Category Color</span>
                            <div class="color-preview" style="background-color: <%= catColor %>"></div>
                            <i class="fas fa-chevron-down"></i>
                        </div>
                        <div class="color-dropdown-content" id="colorDropdown_<%= catId %>">
                            <div class="color-options-grid">
                                <div class="color-option <%= "#60A5FA".equals(catColor) ? "selected" : "" %>" 
                                     style="background-color: #60A5FA" 
                                     onclick="selectColor('<%= catId %>', '#60A5FA')"></div>
                                <div class="color-option <%= "#34D399".equals(catColor) ? "selected" : "" %>" 
                                     style="background-color: #34D399" 
                                     onclick="selectColor('<%= catId %>', '#34D399')"></div>
                                <div class="color-option <%= "#FBBF24".equals(catColor) ? "selected" : "" %>" 
                                     style="background-color: #FBBF24" 
                                     onclick="selectColor('<%= catId %>', '#FBBF24')"></div>
                                <div class="color-option <%= "#F87171".equals(catColor) ? "selected" : "" %>" 
                                     style="background-color: #F87171" 
                                     onclick="selectColor('<%= catId %>', '#F87171')"></div>
                                <div class="color-option <%= "#A78BFA".equals(catColor) ? "selected" : "" %>" 
                                     style="background-color: #A78BFA" 
                                     onclick="selectColor('<%= catId %>', '#A78BFA')"></div>
                                <div class="color-option <%= "#38BDF8".equals(catColor) ? "selected" : "" %>" 
                                     style="background-color: #38BDF8" 
                                     onclick="selectColor('<%= catId %>', '#38BDF8')"></div>
                            </div>
                            <div class="color-options-grid">
                                <div class="color-option <%= "#A3E635".equals(catColor) ? "selected" : "" %>" 
                                     style="background-color: #A3E635" 
                                     onclick="selectColor('<%= catId %>', '#A3E635')"></div>
                                <div class="color-option <%= "#FB923C".equals(catColor) ? "selected" : "" %>" 
                                     style="background-color: #FB923C" 
                                     onclick="selectColor('<%= catId %>', '#FB923C')"></div>
                                <div class="color-option <%= "#C084FC".equals(catColor) ? "selected" : "" %>" 
                                     style="background-color: #C084FC" 
                                     onclick="selectColor('<%= catId %>', '#C084FC')"></div>
                                <div class="color-option <%= "#22D3EE".equals(catColor) ? "selected" : "" %>" 
                                     style="background-color: #22D3EE" 
                                     onclick="selectColor('<%= catId %>', '#22D3EE')"></div>
                                <div class="color-option <%= "#4ADE80".equals(catColor) ? "selected" : "" %>" 
                                     style="background-color: #4ADE80" 
                                     onclick="selectColor('<%= catId %>', '#4ADE80')"></div>
                                <div class="color-option <%= "#FACC15".equals(catColor) ? "selected" : "" %>" 
                                     style="background-color: #FACC15" 
                                     onclick="selectColor('<%= catId %>', '#FACC15')"></div>
                            </div>
                        </div>
                    </div>
                    
                    <!-- Add Expense Form -->
                    <form method="post" class="mb-4">
                        <input type="hidden" name="action" value="addExpense"/>
                        <input type="hidden" name="categoryId" value="<%= catId %>"/>
                        <input type="hidden" name="csrfToken" value="<%= csrfToken %>"/>
                        <div class="row">
                            <div class="col-md-6">
                                <input type="text" name="item" class="form-control mb-2" placeholder="Item name" required>
                            </div>
                            <div class="col-md-4">
                                <input type="number" step="0.01" min="0" max="100000" name="amount" 
                                       class="form-control mb-2" placeholder="Amount" required>
                            </div>
                            <div class="col-md-2">
                                <button class="btn btn-success w-100">
                                    <i class="fas fa-plus"></i>
                                </button>
                            </div>
                        </div>
                    </form>
                    
                    <!-- Expenses List -->
                    <h6 class="mb-3">Recent Expenses</h6>
                    <% if (categoryExpenses != null && !categoryExpenses.isEmpty()) { %>
                        <div class="list-group">
                            <% for (Document expense : categoryExpenses) { 
                                String item = escapeHtml(expense.getString("item"));
                                double amount = expense.getDouble("amount");
                                Date spentAt = expense.getDate("spent_at");
                            %>
                            <div class="list-group-item d-flex justify-content-between align-items-center">
                                <div>
                                    <h6 class="mb-1"><%= item %></h6>
                                    <small class="text-muted"><%= dateFormat.format(spentAt) %></small>
                                </div>
                                <div class="d-flex align-items-center">
                                    <span class="text-danger me-3">&#8377;<%= df.format(amount) %></span>
                                    <form method="post" class="d-inline">
                                        <input type="hidden" name="action" value="deleteExpense"/>
                                        <input type="hidden" name="expenseId" value="<%= expense.getObjectId("_id").toString() %>"/>
                                        <input type="hidden" name="csrfToken" value="<%= csrfToken %>"/>
                                        <button type="submit" class="btn btn-sm btn-outline-danger">
                                            <i class="fas fa-trash"></i>
                                        </button>
                                    </form>
                                </div>
                            </div>
                            <% } %>
                        </div>
                    <% } else { %>
                        <p class="text-muted text-center">No expenses yet.</p>
                    <% } %>
                </div>
            </div>
        </div>
    </div>
    <% } %>

    <!-- Add Category Modal -->
    <div class="modal fade" id="addCategoryModal" tabindex="-1" aria-labelledby="addCategoryModalLabel" aria-hidden="true">
        <div class="modal-dialog">
            <div class="modal-content">
                <div class="modal-header">
                    <h5 class="modal-title" id="addCategoryModalLabel">Add New Category</h5>
                    <button type="button" class="btn-close" data-bs-dismiss="modal" aria-label="Close"></button>
                </div>
                <div class="modal-body">
                    <form method="post" id="addCategoryForm">
                        <input type="hidden" name="action" value="addCategory"/>
                        <input type="hidden" name="csrfToken" value="<%= csrfToken %>"/>
                        <div class="mb-3">
                            <label for="newCategory" class="form-label">Category Name</label>
                            <input type="text" class="form-control" id="newCategory" name="newCategory" 
                                   placeholder="Enter category name" required
                                   pattern="[a-zA-Z0-9\s\-&]{2,50}" 
                                   title="Category name must be 2-50 characters long and contain only letters, numbers, spaces, hyphens, and ampersands.">
                            <div class="form-text">
                                Category name must be 2-50 characters. Only letters, numbers, spaces, hyphens, and ampersands are allowed.
                            </div>
                        </div>
                    </form>
                </div>
                <div class="modal-footer">
                    <button type="button" class="btn btn-secondary" data-bs-dismiss="modal">Cancel</button>
                    <button type="submit" form="addCategoryForm" class="btn btn-primary">Add Category</button>
                </div>
            </div>
        </div>
    </div>

    <!-- Delete Category Modal - FIXED DARK MODE -->
    <div class="modal fade" id="deleteCategoryModal" tabindex="-1" aria-labelledby="deleteCategoryModalLabel" aria-hidden="true">
        <div class="modal-dialog modal-dialog-centered">
            <div class="modal-content">
                <div class="modal-header">
                    <h5 class="modal-title" id="deleteCategoryModalLabel">Delete Category</h5>
                    <button type="button" class="btn-close" data-bs-dismiss="modal" aria-label="Close"></button>
                </div>
                <div class="modal-body">
                    <p>Are you sure you want to delete the category "<span id="deleteCatName"></span>"?</p>
                    <p class="text-danger"><small>This will also delete all expenses in this category. This action cannot be undone.</small></p>
                    <form method="post" id="deleteCategoryForm">
                        <input type="hidden" name="action" value="deleteCategory"/>
                        <input type="hidden" name="categoryId" id="deleteCatId"/>
                        <input type="hidden" name="csrfToken" value="<%= csrfToken %>"/>
                    </form>
                </div>
                <div class="modal-footer">
                    <button type="button" class="btn btn-secondary" data-bs-dismiss="modal">Cancel</button>
                    <button type="submit" form="deleteCategoryForm" class="btn btn-danger">Delete Category</button>
                </div>
            </div>
        </div>
    </div>

    <!-- Bottom Navigation -->
    <nav class="bottom-nav">
        <div class="container">
            <div class="nav-grid">
                <a href="tracker.jsp" class="nav-item">
                    <i class="fas fa-home nav-icon"></i>
                    <span class="nav-label">Home</span>
                </a>
                <a href="categories.jsp" class="nav-item active">
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

        // Category Color Functions
        function toggleColorDropdown(catId) {
            const dropdown = document.getElementById('colorDropdown_' + catId);
            if (dropdown) {
                dropdown.classList.toggle('show');
            }
        }

        function selectColor(catId, color) {
            const dropdown = document.getElementById('colorDropdown_' + catId);
            if (dropdown) {
                dropdown.classList.remove('show');
            }
            
            // Submit form immediately
            const form = document.createElement('form');
            form.method = 'POST';
            form.action = window.location.href;
            
            const actionInput = document.createElement('input');
            actionInput.type = 'hidden';
            actionInput.name = 'action';
            actionInput.value = 'updateCategoryColor';
            
            const catIdInput = document.createElement('input');
            catIdInput.type = 'hidden';
            catIdInput.name = 'categoryId';
            catIdInput.value = catId;
            
            const colorInput = document.createElement('input');
            colorInput.type = 'hidden';
            colorInput.name = 'color';
            colorInput.value = color;
            
            const csrfInput = document.createElement('input');
            csrfInput.type = 'hidden';
            csrfInput.name = 'csrfToken';
            csrfInput.value = '<%= csrfToken %>';
            
            form.appendChild(actionInput);
            form.appendChild(catIdInput);
            form.appendChild(colorInput);
            form.appendChild(csrfInput);
            document.body.appendChild(form);
            
            form.submit();
        }

        // Close color dropdown when clicking outside
        document.addEventListener('click', function(e) {
            if (!e.target.closest('.color-picker-dropdown')) {
                document.querySelectorAll('.color-dropdown-content').forEach(dropdown => {
                    dropdown.classList.remove('show');
                });
            }
        });

        // Open category modal function
        function openCategoryModal(catId) {
            const modal = new bootstrap.Modal(document.getElementById('modal_' + catId));
            modal.show();
        }

        // Delete category function
        function showDeleteModal(catId, catName) {
            const deleteCatName = document.getElementById('deleteCatName');
            const deleteCatId = document.getElementById('deleteCatId');
            
            if (deleteCatName && deleteCatId) {
                deleteCatName.textContent = catName;
                deleteCatId.value = catId;
                
                const deleteModal = new bootstrap.Modal(document.getElementById('deleteCategoryModal'));
                deleteModal.show();
            }
        }

        // Delete category selection function
        function showDeleteCategorySelection() {
            // Close the sidebar menu
            toggleMenu();
            
            // Create selection modal
            const selectionModal = `
                <div class="modal fade" id="deleteSelectionModal" tabindex="-1">
                    <div class="modal-dialog modal-lg">
                        <div class="modal-content">
                            <div class="modal-header">
                                <h5 class="modal-title">Select Category to Delete</h5>
                                <button type="button" class="btn-close" data-bs-dismiss="modal"></button>
                            </div>
                            <div class="modal-body">
                                <div class="categories-grid">
                                    <% for (Document category : categories) { 
                                        String catId = category.getObjectId("_id").toString();
                                        String catName = escapeHtml(category.getString("name"));
                                        String catColor = category.getString("color");
                                    %>
                                    <div class="category-tile" style="--color: <%= catColor %>;"
                                         onclick="confirmDeleteSelection('<%= catId %>', '<%= catName %>')">
                                        <%= catName %>
                                    </div>
                                    <% } %>
                                </div>
                            </div>
                            <div class="modal-footer">
                                <button type="button" class="btn btn-secondary" data-bs-dismiss="modal">Cancel</button>
                            </div>
                        </div>
                    </div>
                </div>
            `;
            
            // Remove existing modal if any
            const existingModal = document.getElementById('deleteSelectionModal');
            if (existingModal) {
                existingModal.remove();
            }
            
            // Add modal to body
            document.body.insertAdjacentHTML('beforeend', selectionModal);
            
            // Show the modal
            const modal = new bootstrap.Modal(document.getElementById('deleteSelectionModal'));
            modal.show();
        }

        // Confirm deletion for selected category
        function confirmDeleteSelection(catId, catName) {
            // Close the selection modal
            const selectionModal = bootstrap.Modal.getInstance(document.getElementById('deleteSelectionModal'));
            selectionModal.hide();
            
            // Show the delete confirmation modal
            showDeleteModal(catId, catName);
        }

        // Menu Functions
        function showColorGuide() {
            alert('Color Guide:\n\nEach category has a unique color for better visual organization. You can change colors anytime from the category settings.');
        }

        function exportCategories() {
            alert('Export functionality would be implemented here.');
        }

        function logout() {
            if (confirm('Are you sure you want to log out?')) {
                window.location.href = 'logout.jsp';
            }
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