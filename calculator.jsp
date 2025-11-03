<%@ page import="java.util.*" %>
<%
    // Check if user is logged in
    String loggedInUserId = (String) session.getAttribute("userId");
    if (loggedInUserId == null) {
        response.sendRedirect("login.jsp");
        return;
    }

    String result = "";
    String errorMessage = null;
    String expression = request.getParameter("expression") != null ? request.getParameter("expression") : "";
    
    // Handle calculation
    if (request.getMethod().equals("POST") && expression != null && !expression.trim().isEmpty()) {
        try {
            result = evaluateExpression(expression.trim());
        } catch (Exception e) {
            errorMessage = "Invalid expression: " + e.getMessage();
        }
    }
%>

<%!
    // Simple expression evaluation method
    private String evaluateExpression(String expr) throws Exception {
        // Remove any whitespace
        expr = expr.replaceAll("\\s+", "");
        
        // Validate expression contains only numbers and basic operators
        if (!expr.matches("^[0-9+\\-*/().]+$")) {
            throw new Exception("Invalid characters in expression");
        }
        
        // Use JavaScript engine for evaluation (safe for basic math)
        try {
            javax.script.ScriptEngineManager manager = new javax.script.ScriptEngineManager();
            javax.script.ScriptEngine engine = manager.getEngineByName("JavaScript");
            Object evalResult = engine.eval(expr);
            
            if (evalResult instanceof Number) {
                double value = ((Number) evalResult).doubleValue();
                // Format to remove trailing .0 if integer
                if (value == (long) value) {
                    return String.format("%d", (long) value);
                } else {
                    return String.format("%.2f", value);
                }
            }
            return evalResult.toString();
        } catch (Exception e) {
            throw new Exception("Unable to evaluate expression");
        }
    }
%>

<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>Personal Finance Tracker - Calculator</title>
    
    <link rel="icon" type="image/png" href="icon.png">
    <link href="https://cdn.jsdelivr.net/npm/bootstrap@5.3.3/dist/css/bootstrap.min.css" rel="stylesheet">
    <link href="https://cdnjs.cloudflare.com/ajax/libs/font-awesome/6.0.0/css/all.min.css" rel="stylesheet">
    
    <style>
        :root {
            --primary-blue: #1e88e5;
            --dark-blue: #1565c0;
            --light-blue: #64b5f6;
            --light-bg: #f5f9ff;
            --button-light: #e3f2fd;
        }
        
        body {
            background: var(--light-bg);
            font-family: 'Segoe UI', Tahoma, Geneva, Verdana, sans-serif;
            padding-bottom: 80px;
            min-height: 100vh;
        }
        
        .app-header {
            background: linear-gradient(135deg, var(--primary-blue) 0%, var(--dark-blue) 100%);
            color: white;
            padding: 1.5rem 0;
            margin-bottom: 2rem;
            box-shadow: 0 4px 12px rgba(0,0,0,0.1);
        }
        
        .app-title {
            font-weight: 800;
            text-align: center;
            margin: 0;
            font-size: 2.2rem;
            background: linear-gradient(45deg, #fff 0%, #e3f2fd 100%);
            -webkit-background-clip: text;
            -webkit-text-fill-color: transparent;
            background-clip: text;
        }
        
        .calculator-container {
            max-width: 400px;
            margin: 0 auto;
            background: white;
            border-radius: 16px;
            box-shadow: 0 8px 25px rgba(30, 136, 229, 0.15);
            overflow: hidden;
        }
        
        .calculator-display {
            background: linear-gradient(135deg, #0d47a1 0%, #1976d2 100%);
            color: white;
            padding: 1.5rem;
            text-align: right;
            font-family: 'Courier New', monospace;
            min-height: 100px;
            display: flex;
            flex-direction: column;
            justify-content: flex-end;
        }
        
        .calculator-expression {
            font-size: 0.9rem;
            color: #bbdefb;
            margin-bottom: 0.5rem;
            min-height: 1.2rem;
            word-break: break-all;
        }
        
        .calculator-result {
            font-size: 2rem;
            font-weight: bold;
            word-break: break-all;
        }
        
        .calculator-buttons {
            display: grid;
            grid-template-columns: repeat(4, 1fr);
            gap: 1px;
            background: #e3f2fd;
        }
        
        .calc-btn {
            border: none;
            padding: 1.5rem;
            font-size: 1.2rem;
            background: white;
            cursor: pointer;
            transition: all 0.2s;
            font-weight: 600;
        }
        
        .calc-btn:hover {
            background: var(--button-light);
        }
        
        .calc-btn:active {
            background: #bbdefb;
        }
        
        .calc-btn.operator {
            background: var(--light-blue);
            color: white;
        }
        
        .calc-btn.operator:hover {
            background: var(--primary-blue);
        }
        
        .calc-btn.equals {
            background: var(--primary-blue);
            color: white;
            grid-column: span 2;
        }
        
        .calc-btn.equals:hover {
            background: var(--dark-blue);
        }
        
        .calc-btn.clear {
            background: #e53935;
            color: white;
        }
        
        .calc-btn.clear:hover {
            background: #c62828;
        }
        
        .calc-btn.zero {
            grid-column: span 2;
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
            background: var(--primary-blue);
            color: white;
        }
        
        .nav-item:hover {
            background: #e9ecef;
            color: var(--primary-blue);
        }
        
        .nav-item.active:hover {
            background: var(--dark-blue);
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
            .calculator-container {
                margin: 0 1rem;
            }
            
            .calc-btn {
                padding: 1.2rem;
                font-size: 1.1rem;
            }
        }
    </style>
</head>
<body>
    <!-- Header -->
    <div class="app-header">
        <div class="container">
            <h1 class="app-title">Calculator</h1>
        </div>
    </div>

    <!-- Alert Messages -->
    <% if (errorMessage != null) { %>
    <div class="alert alert-danger alert-dismissible fade show mx-3" role="alert">
        <i class="fas fa-exclamation-triangle me-2"></i><%= errorMessage %>
        <button type="button" class="btn-close" data-bs-dismiss="alert"></button>
    </div>
    <% } %>

    <div class="container mt-4">
        <div class="calculator-container">
            <!-- Calculator Display -->
            <div class="calculator-display">
                <div class="calculator-expression" id="expressionDisplay">
                    <%= expression %>
                </div>
                <div class="calculator-result" id="resultDisplay">
                    <%= result %>
                </div>
            </div>
            
            <!-- Calculator Buttons -->
            <div class="calculator-buttons">
                <!-- Row 1 -->
                <button class="calc-btn clear" onclick="clearCalculator()">AC</button>
                <button class="calc-btn" onclick="appendToExpression('(')">(</button>
                <button class="calc-btn" onclick="appendToExpression(')')">)</button>
                <button class="calc-btn operator" onclick="appendToExpression('/')">/</button>
                
                <!-- Row 2 -->
                <button class="calc-btn" onclick="appendToExpression('7')">7</button>
                <button class="calc-btn" onclick="appendToExpression('8')">8</button>
                <button class="calc-btn" onclick="appendToExpression('9')">9</button>
                <button class="calc-btn operator" onclick="appendToExpression('*')">×</button>
                
                <!-- Row 3 -->
                <button class="calc-btn" onclick="appendToExpression('4')">4</button>
                <button class="calc-btn" onclick="appendToExpression('5')">5</button>
                <button class="calc-btn" onclick="appendToExpression('6')">6</button>
                <button class="calc-btn operator" onclick="appendToExpression('-')">-</button>
                
                <!-- Row 4 -->
                <button class="calc-btn" onclick="appendToExpression('1')">1</button>
                <button class="calc-btn" onclick="appendToExpression('2')">2</button>
                <button class="calc-btn" onclick="appendToExpression('3')">3</button>
                <button class="calc-btn operator" onclick="appendToExpression('+')">+</button>
                
                <!-- Row 5 -->
                <button class="calc-btn zero" onclick="appendToExpression('0')">0</button>
                <button class="calc-btn" onclick="appendToExpression('.')">.</button>
                <button class="calc-btn equals" onclick="calculate()">=</button>
            </div>
        </div>
    </div>

    <!-- Hidden form for calculation -->
    <form method="post" id="calcForm" style="display: none;">
        <input type="hidden" name="expression" id="expressionInput">
    </form>

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
                <a href="statistics.jsp" class="nav-item">
                    <i class="fas fa-chart-pie nav-icon"></i>
                    <span class="nav-label">Statistics</span>
                </a>
                <a href="calculator.jsp" class="nav-item active">
                    <i class="fas fa-calculator nav-icon"></i>
                    <span class="nav-label">Calculator</span>
                </a>
            </div>
        </div>
    </nav>

    <script src="https://cdn.jsdelivr.net/npm/bootstrap@5.3.3/dist/js/bootstrap.bundle.min.js"></script>
    <script>
        let currentExpression = '<%= expression %>';
        let currentResult = '<%= result %>';

        function appendToExpression(value) {
            currentExpression += value;
            updateDisplay();
        }

        function clearCalculator() {
            currentExpression = '';
            currentResult = '';
            updateDisplay();
        }

        function calculate() {
            if (currentExpression.trim() !== '') {
                document.getElementById('expressionInput').value = currentExpression;
                document.getElementById('calcForm').submit();
            }
        }

        function updateDisplay() {
            document.getElementById('expressionDisplay').textContent = currentExpression;
            document.getElementById('resultDisplay').textContent = currentResult;
        }

        // Keyboard support
        document.addEventListener('keydown', function(event) {
            const key = event.key;
            
            if (key >= '0' && key <= '9') {
                appendToExpression(key);
            } else if (['+', '-', '*', '/', '.', '(', ')'].includes(key)) {
                appendToExpression(key);
            } else if (key === 'Enter' || key === '=') {
                calculate();
            } else if (key === 'Escape' || key === 'c' || key === 'C') {
                clearCalculator();
            } else if (key === 'Backspace') {
                currentExpression = currentExpression.slice(0, -1);
                updateDisplay();
            }
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
            
            updateDisplay();
        });
    </script>
</body>
</html>