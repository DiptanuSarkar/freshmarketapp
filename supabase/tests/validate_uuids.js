/**
 * UUID Validation Script (Section B)
 * Recursively verifies that every hard-coded UUID value across all SQL files
 * in supabase/ (migrations, seed.sql, tests) parses as a valid PostgreSQL hexadecimal UUID [0-9a-f].
 */

const fs = require('fs');
const path = require('path');

const UUID_HEX_REGEX = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;
// Pattern detecting 36-char hyphenated alphanumeric UUID candidates
const CANDIDATE_REGEX = /\b([0-9a-zA-Z]{8}-[0-9a-zA-Z]{4}-[0-9a-zA-Z]{4}-[0-9a-zA-Z]{4}-[0-9a-zA-Z]{12})\b/g;

function findSqlFiles(dir) {
  let results = [];
  const entries = fs.readdirSync(dir, { withFileTypes: true });
  for (const entry of entries) {
    const fullPath = path.join(dir, entry.name);
    if (entry.isDirectory()) {
      if (entry.name !== '.temp' && entry.name !== 'node_modules') {
        results.push(...findSqlFiles(fullPath));
      }
    } else if (entry.name.endsWith('.sql')) {
      results.push(fullPath);
    }
  }
  return results;
}

const supabaseDir = path.resolve(__dirname, '..');
const filesToAudit = findSqlFiles(supabaseDir);

let totalUuidsChecked = 0;
let errors = [];

for (const filePath of filesToAudit) {
  const content = fs.readFileSync(filePath, 'utf8');
  const lines = content.split('\n');

  lines.forEach((line, lineIndex) => {
    let match;
    while ((match = CANDIDATE_REGEX.exec(line)) !== null) {
      const candidate = match[1];
      totalUuidsChecked++;

      if (!UUID_HEX_REGEX.test(candidate)) {
        errors.push({
          file: path.relative(process.cwd(), filePath),
          line: lineIndex + 1,
          value: candidate,
          error: 'Contains non-hexadecimal characters'
        });
      }
    }
  });
}

console.log('================================================================');
console.log('FreshMarket Comprehensive PostgreSQL UUID Validation Audit');
console.log('================================================================');
console.log(`Audited ${filesToAudit.length} SQL files across supabase directory.`);
console.log(`Total candidate UUIDs audited: ${totalUuidsChecked}`);

if (errors.length > 0) {
  console.error(`FAILED: Found ${errors.length} invalid UUID(s):`);
  errors.forEach(err => {
    console.error(`  - [${err.file}:${err.line}] "${err.value}" (${err.error})`);
  });
  process.exit(1);
} else {
  console.log(`SUCCESS: All ${totalUuidsChecked} UUIDs across all SQL files are strictly valid hexadecimal [0-9a-f]!`);
  process.exit(0);
}
