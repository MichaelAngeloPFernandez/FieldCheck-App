const fs = require('fs');
const path = require('path');

const rootDir = process.argv[2] || '.';
const outputFile = 'fieldcheck_codebase_compiled.txt';

const excludeDirs = ['node_modules', '.git', '.idea', '.vscode', 'build', '.dart_tool', 'android', 'ios', 'linux', 'macos', 'windows', 'web', 'test', 'assets'];
const includeExts = ['.js', '.dart', '.html', '.css', '.yaml', '.json', '.puml', '.md', '.sh', '.bat', '.yaml', '.env.example'];

let allFiles = [];

function walk(dir) {
    const files = fs.readdirSync(dir);
    for (const file of files) {
        const fullPath = path.join(dir, file);
        const stat = fs.statSync(fullPath);
        if (stat.isDirectory()) {
            if (!excludeDirs.includes(file)) {
                walk(fullPath);
            }
        } else {
            const ext = path.extname(file);
            if (includeExts.includes(ext)) {
                // Additional check for large generated files or lock files
                if (file === 'package-lock.json' || file === 'pubspec.lock') continue;
                allFiles.push(fullPath);
            }
        }
    }
}

console.log('Scanning files...');
walk(rootDir);

let output = '# 📚 FIELDCHECK 2.0 CODEBASE COMPILATION\n\n';
output += '## 📋 TABLE OF CONTENTS\n\n';

allFiles.forEach((file, index) => {
    const relativePath = path.relative(rootDir, file);
    output += `${index + 1}. [${relativePath}](#${relativePath.replace(/\\/g, '-').replace(/\./g, '-')})\n`;
});

output += '\n---\n\n';

allFiles.forEach((file) => {
    const relativePath = path.relative(rootDir, file);
    const content = fs.readFileSync(file, 'utf8');
    output += `\n### 📄 FILE: ${relativePath}\n`;
    output += `<a id="${relativePath.replace(/\\/g, '-').replace(/\./g, '-')}"></a>\n`;
    output += '```' + (path.extname(file).slice(1) || 'text') + '\n';
    output += content;
    output += '\n```\n';
    output += '\n---\n';
});

fs.writeFileSync(outputFile, output);
console.log(`Successfully compiled ${allFiles.length} files into ${outputFile}`);
