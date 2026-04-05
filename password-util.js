#!/usr/bin/env node

/**
 * Password Utility Script for LMS
 * ================================
 * bcrypt is a ONE-WAY hash. It cannot be decrypted.
 * This script helps you verify, generate, and reset passwords.
 *
 * Usage:
 *   node scripts/password-util.js verify <plain_password> <hash>
 *   node scripts/password-util.js generate <plain_password>
 *   node scripts/password-util.js reset <user_email> <new_password>
 *   node scripts/password-util.js lookup <user_email>
 */

const path = require('path');
const MODULE_PATH = path.resolve(__dirname, '../user-service/node_modules');

// Resolve dependencies from user-service/node_modules
const dotenv = require(path.join(MODULE_PATH, 'dotenv'));
dotenv.config({ path: path.resolve(__dirname, '../user-service/.env') });

const bcrypt = require(path.join(MODULE_PATH, 'bcryptjs'));
const { Pool } = require(path.join(MODULE_PATH, 'pg'));

const SALT_ROUNDS = 10;

// ─── Colors for terminal output ──────────────────────────────────────────────
const green = (s) => `\x1b[32m${s}\x1b[0m`;
const red = (s) => `\x1b[31m${s}\x1b[0m`;
const yellow = (s) => `\x1b[33m${s}\x1b[0m`;
const cyan = (s) => `\x1b[36m${s}\x1b[0m`;
const bold = (s) => `\x1b[1m${s}\x1b[0m`;

// ─── Database connection (only created when needed) ──────────────────────────
function getPool() {
  const connectionString = process.env.DATABASE_URL;
  if (!connectionString) {
    console.error(red('ERROR: DATABASE_URL not found in user-service/.env'));
    process.exit(1);
  }
  return new Pool({ connectionString });
}

// ─── VERIFY: Check if a plain password matches a hash ────────────────────────
async function verify(plainPassword, hash) {
  console.log(cyan('\nVerifying password against hash...\n'));
  console.log(`  Password:  ${plainPassword}`);
  console.log(`  Hash:      ${hash}\n`);

  const isMatch = await bcrypt.compare(plainPassword, hash);

  if (isMatch) {
    console.log(green('  MATCH — the password is correct.\n'));
  } else {
    console.log(red('  NO MATCH — the password is wrong.\n'));
  }
}

// ─── GENERATE: Create a bcrypt hash from a plain password ────────────────────
async function generate(plainPassword) {
  console.log(cyan('\nGenerating bcrypt hash...\n'));
  console.log(`  Password:    ${plainPassword}`);
  console.log(`  Salt rounds: ${SALT_ROUNDS}\n`);

  const salt = await bcrypt.genSalt(SALT_ROUNDS);
  const hash = await bcrypt.hash(plainPassword, salt);

  console.log(green(`  Hash: ${hash}\n`));
  console.log(`  You can use this hash directly in a SQL UPDATE:`);
  console.log(yellow(`  UPDATE users SET password_hash = '${hash}' WHERE email = 'user@example.com';\n`));
}

// ─── LOOKUP: Find a user by email and show their info ────────────────────────
async function lookup(email) {
  console.log(cyan(`\nLooking up user: ${email}\n`));

  const pool = getPool();
  try {
    const result = await pool.query(
      `SELECT user_id, email, first_name, last_name, role,
              password_hash IS NOT NULL AS has_password,
              LENGTH(password_hash) AS hash_length,
              created_at, updated_at
       FROM users
       WHERE LOWER(email) = LOWER($1)`,
      [email]
    );

    if (result.rows.length === 0) {
      console.log(red(`  No user found with email: ${email}\n`));
      return;
    }

    const user = result.rows[0];
    console.log(bold('  User found:\n'));
    console.log(`  ID:           ${user.user_id}`);
    console.log(`  Email:        ${user.email}`);
    console.log(`  Name:         ${user.first_name} ${user.last_name}`);
    console.log(`  Role:         ${user.role}`);
    console.log(`  Has password: ${user.has_password ? green('Yes') : red('No')}`);
    console.log(`  Hash length:  ${user.hash_length || 'N/A'}`);
    console.log(`  Created:      ${user.created_at}`);
    console.log(`  Updated:      ${user.updated_at}\n`);
  } finally {
    await pool.end();
  }
}

// ─── RESET: Update a user's password in the database ─────────────────────────
async function reset(email, newPassword) {
  console.log(cyan(`\nResetting password for: ${email}\n`));

  if (newPassword.length < 8) {
    console.log(red('  ERROR: Password must be at least 8 characters.\n'));
    process.exit(1);
  }

  const pool = getPool();
  try {
    const userCheck = await pool.query(
      'SELECT user_id, email, first_name, last_name FROM users WHERE LOWER(email) = LOWER($1)',
      [email]
    );

    if (userCheck.rows.length === 0) {
      console.log(red(`  No user found with email: ${email}\n`));
      return;
    }

    const user = userCheck.rows[0];
    console.log(`  Found user: ${user.first_name} ${user.last_name} (${user.user_id})`);

    const hash = await bcrypt.hash(newPassword, SALT_ROUNDS);

    await pool.query(
      'UPDATE users SET password_hash = $1, updated_at = NOW() WHERE LOWER(email) = LOWER($2)',
      [hash, email]
    );

    console.log(green(`\n  Password reset successfully.`));
    console.log(`  New hash: ${hash}\n`);
  } finally {
    await pool.end();
  }
}

// ─── HELP ────────────────────────────────────────────────────────────────────
function showHelp() {
  console.log(`
${bold('LMS Password Utility')}
${cyan('bcrypt is a one-way hash. Passwords CANNOT be decrypted.')}
${cyan('This tool helps you verify, generate, and reset passwords.')}

${bold('Commands:')}

  ${green('verify')} <password> <hash>
    Check if a plain text password matches a bcrypt hash.
    Example: node scripts/password-util.js verify "demo" "$2a\\$10\\$abc..."

  ${green('generate')} <password>
    Generate a bcrypt hash from a plain text password.
    Example: node scripts/password-util.js generate "MyNewPassword123!"

  ${green('lookup')} <email>
    Look up a user by email and show their details.
    Example: node scripts/password-util.js lookup "john@example.com"

  ${green('reset')} <email> <new_password>
    Reset a user's password in the database.
    Example: node scripts/password-util.js reset "john@example.com" "NewPass123!"

${bold('Default passwords in this system:')}
  Students:    demo
  Instructors: instructor@1234
  Super Admin: Algoristics@#2025
`);
}

// ─── MAIN ────────────────────────────────────────────────────────────────────
async function main() {
  const [command, ...args] = process.argv.slice(2);

  switch (command) {
    case 'verify':
      if (args.length < 2) {
        console.log(red('\n  Usage: verify <password> <hash>\n'));
        process.exit(1);
      }
      await verify(args[0], args[1]);
      break;

    case 'generate':
      if (args.length < 1) {
        console.log(red('\n  Usage: generate <password>\n'));
        process.exit(1);
      }
      await generate(args[0]);
      break;

    case 'lookup':
      if (args.length < 1) {
        console.log(red('\n  Usage: lookup <email>\n'));
        process.exit(1);
      }
      await lookup(args[0]);
      break;

    case 'reset':
      if (args.length < 2) {
        console.log(red('\n  Usage: reset <email> <new_password>\n'));
        process.exit(1);
      }
      await reset(args[0], args[1]);
      break;

    default:
      showHelp();
  }
}

main().catch((err) => {
  console.error(red(`\nError: ${err.message}\n`));
  process.exit(1);
});
