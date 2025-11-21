const path = require('path');
const http = require('http');
const fs = require('fs');

const port = process.env.WEB_PORT || 8080;
const webDir = path.join(__dirname, 'field_check', 'build', 'web');

const server = http.createServer((req, res) => {
  let filePath = path.join(webDir, req.url);
  
  // Default to index.html for SPA routing
  if (filePath === webDir || filePath === webDir + '/') {
    filePath = path.join(webDir, 'index.html');
  }
  
  // If trying to access a non-existent file, serve index.html
  if (!fs.existsSync(filePath) && !req.url.includes('.')) {
    filePath = path.join(webDir, 'index.html');
  }
  
  const ext = path.extname(filePath).toLowerCase();
  const contentTypes = {
    '.html': 'text/html; charset=utf-8',
    '.js': 'application/javascript',
    '.css': 'text/css',
    '.json': 'application/json',
    '.png': 'image/png',
    '.jpg': 'image/jpeg',
    '.gif': 'image/gif',
    '.svg': 'image/svg+xml',
    '.woff': 'font/woff',
    '.woff2': 'font/woff2',
    '.ttf': 'font/ttf',
    '.eot': 'application/vnd.ms-fontobject',
  };

  fs.readFile(filePath, (err, content) => {
    if (err) {
      res.writeHead(404, { 'Content-Type': 'text/html' });
      res.end('<h1>404 - Not Found</h1>');
    } else {
      const contentType = contentTypes[ext] || 'text/plain';
      res.writeHead(200, { 'Content-Type': contentType });
      res.end(content, 'utf-8');
    }
  });
});

server.listen(port, () => {
  console.log(`✅ Frontend web server running at http://localhost:${port}`);
});
