/**
 * UUID Validation Script (Section B)
 * Verifies that every hard-coded UUID value in supabase/seed.sql and
 * supabase/tests/database/*.sql is a valid PostgreSQL hexadecimal UUID.
 */

const fs = require('fs');
const path = require('path');

const UUID_REGEX = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;
// Pattern to detect string literals that look like intended UUIDs (e.g. 36 chars with dashes)
const CANDIDATE_REGEX = /'([0-9a-zA-Z]{8}-[0-9a-zA-Z]{4}-[0-9a-zA-Z]{4}-[0-9a-zA-Z]{4}-[0-9a-zA-Z]{12})'/g;

const filesToAudit = [
  path.join(__dirname, '..', 'seed.sql'),
  path.join(__dirname, 'database', '01_schema_and_trigger_test.sql'),
  path.join(__dirname, 'database', '02_security_and_rls_test.sql')
];

let totalUuidsChecked = 0;
let errors = [];

for (const filePath of filesToAudit) {
  if (!fs.existsSync(filePath)) {
    console.error(`File not found: ${filePath}`);
    process.exit(1);
  }

  const content = fs.readFileSync(filePath, 'utf8');
  const lines = content.split('\n');

  lines.forEach((line, lineIndex) => {
    let match;
    while ((match = CANDIDATE_REGEX.exec(line)) !== null) {
      const candidate = match[1];
      totalUuidsChecked++;

      if (!UUID_REGEX.test(candidate)) {
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
console.log('FreshMarket UUID Validation Audit');
console.log('================================================================');
console.log(`Total candidate UUIDs audited: ${totalUuidsChecked}`);

if (errors.length > 0) {
  console.error(`FAILED: Found ${errors.length} invalid UUID(s):`);
  errors.forEach(err => {
    console.error(`  - [${err.file}:${err.line}] "${err.value}" (${err.error})`);
  });
  process.exit(1);
} else {
  console.log(`SUCCESS: All ${totalUuidsChecked} UUIDs are strictly valid hexadecimal characters [0-9a-f]!`);
  process.exit(0);
}
