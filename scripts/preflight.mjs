import { existsSync, readFileSync } from "node:fs";
import { spawnSync } from "node:child_process";

let okCount = 0;
let warnCount = 0;
let errorCount = 0;

function ok(message) {
  okCount += 1;
  console.log(`OK: ${message}`);
}

function warn(message) {
  warnCount += 1;
  console.log(`WARN: ${message}`);
}

function fail(message) {
  errorCount += 1;
  console.log(`ERROR: ${message}`);
}

function npmCommand() {
  return process.platform === "win32" ? "npm.cmd" : "npm";
}

function envValues() {
  if (!existsSync(".env")) {
    return {};
  }
  const values = {};
  const lines = readFileSync(".env", "utf8").split(/\r?\n/);
  for (const line of lines) {
    const trimmed = line.trim();
    if (!trimmed || trimmed.startsWith("#") || !trimmed.includes("=")) {
      continue;
    }
    const index = trimmed.indexOf("=");
    const key = trimmed.slice(0, index);
    let value = trimmed.slice(index + 1);
    value = value.replace(/^"/, "").replace(/"$/, "");
    if (value) {
      values[key] = value;
    }
  }
  return values;
}

console.log("Agentic Spending Analysis Assistant preflight");
console.log("Checking local tools and setup files...\n");

const nodeVersion = process.version;
const nodeMajor = Number.parseInt(nodeVersion.replace(/^v/, "").split(".")[0] ?? "0", 10);
if (nodeMajor >= 26) {
  warn(`Node is installed (${nodeVersion}). Node 20-24 is recommended; npm run dev will use a compatible local runtime when one is available.`);
} else if (nodeMajor >= 20) {
  ok(`Node is installed (${nodeVersion}).`);
} else {
  warn(`Node is installed (${nodeVersion}), but Node 20-24 is recommended for this project.`);
}

const npmResult = process.platform === "win32"
  ? spawnSync(process.env.ComSpec || "cmd.exe", ["/d", "/s", "/c", "npm.cmd -v"], { encoding: "utf8" })
  : spawnSync(npmCommand(), ["-v"], { encoding: "utf8" });
if (npmResult.status === 0) {
  ok(`npm is installed (${npmResult.stdout.trim()}).`);
} else {
  fail("npm is not installed or is not on PATH. Installing Node from https://nodejs.org/ usually installs npm too.");
}

if (existsSync("package.json")) {
  ok("package.json found.");
} else {
  fail("package.json was not found. Run this command from the project folder.");
}

if (existsSync("node_modules")) {
  ok("Dependencies are installed.");
} else {
  warn("node_modules is missing. Run npm install before npm run dev.");
}

const values = envValues();
if (existsSync(".env")) {
  ok(".env found.");
} else {
  warn(".env is missing. Copy .env.example to .env and fill in your Drive, Sheet, AI, and email settings.");
}

for (const key of ["GOOGLE_DRIVE_FOLDER_ID", "GOOGLE_SHEET_ID", "AI_PROVIDER", "AI_MODEL", "AI_API_KEY", "SINGLE_USER_EMAIL"]) {
  if (values[key]) {
    ok(`${key} is set.`);
  } else {
    warn(`${key} is not set in .env.`);
  }
}

const serviceAccountKey = values.GOOGLE_SERVICE_ACCOUNT_KEY;
if (serviceAccountKey) {
  if (existsSync(serviceAccountKey)) {
    ok("Google service account key file exists.");
  } else {
    warn("GOOGLE_SERVICE_ACCOUNT_KEY is set, but the file was not found. Share the Drive folder and Sheet with the service account after adding the key file.");
  }
} else {
  warn("GOOGLE_SERVICE_ACCOUNT_KEY is not set. Service-account setup is the recommended MVP path.");
}

console.log(`\nPreflight complete: ${okCount} ok, ${warnCount} warnings, ${errorCount} errors.`);

if (errorCount > 0) {
  console.log("Fix the errors above before starting the app.");
  process.exit(1);
}

console.log(`Next step: ${npmCommand()} install, then ${npmCommand()} run dev.`);
