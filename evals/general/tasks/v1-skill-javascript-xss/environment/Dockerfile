FROM bench-base:python-3.12

WORKDIR /app

RUN cat > /app/page.html <<'EOF'
<!DOCTYPE html>
<html>
<body>
  <h1>Search</h1>
  <div id="result"></div>
  <script>
    const q = new URLSearchParams(window.location.search).get('q') || '';
    document.title = "Search: " + q;
    document.getElementById('result').innerHTML = '<p>Results for: ' + q + '</p>';
    var script = "<img src=x onerror=alert(1)>";
  </script>
</body>
</html>
EOF