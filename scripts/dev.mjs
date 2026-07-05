import { existsSync, readdirSync } from "node:fs";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";
import { homedir } from "node:os";
import { spawnSync } from "node:child_process";

const projectDir = dirname(dirname(fileURLToPath(import.meta.url)));
const nodeExe = process.platform === "win32" ? "node.exe" : "node";
const nextBin = join(projectDir, "node_modules", "next", "dist", "bin", "next");

function nodeMajor(executable) {
  const result = spawnSync(executable, ["-p", "process.versions.node.split('.')[0]"], {
    encoding: "utf8",
  });
  if (result.status !== 0) {
    return 0;
  }
  return Number.parseInt(result.stdout.trim(), 10) || 0;
}

function isSupportedNode(executable) {
  const major = nodeMajor(executable);
  return major >= 20 && major < 26;
}

function findBundledNode() {
  const root = join(homedir(), ".cache");
  const suffix = join("codex-primary-runtime", "dependencies", "node", "bin", nodeExe);
  const stack = [root];

  while (stack.length > 0) {
    const current = stack.pop();
    if (!current || !existsSync(current)) {
      continue;
    }
    const candidate = join(current, suffix);
    if (existsSync(candidate)) {
      return candidate;
    }
    let entries = [];
    try {
      entries = readdirSync(current, { withFileTypes: true });
    } catch {
      continue;
    }
    for (const entry of entries) {
      if (entry.isDirectory()) {
        stack.push(join(current, entry.name));
      }
    }
  }
  return null;
}

if (!existsSync(nextBin)) {
  console.error("ERROR: Next.js was not found. Run npm install before npm run dev.");
  process.exit(1);
}

let selectedNode = process.execPath;

if (!isSupportedNode(selectedNode)) {
  const devNode = process.env.DEV_NODE;
  if (devNode && existsSync(devNode) && isSupportedNode(devNode)) {
    console.log(`Using DEV_NODE=${devNode} for Next.js development.`);
    selectedNode = devNode;
  } else {
    const bundledNode = findBundledNode();
    if (bundledNode && isSupportedNode(bundledNode)) {
      const version = spawnSync(bundledNode, ["-v"], { encoding: "utf8" }).stdout.trim();
      console.log(`Using bundled Node ${version} for Next.js development.`);
      selectedNode = bundledNode;
    }
  }
}

if (!isSupportedNode(selectedNode)) {
  const version = spawnSync(process.execPath, ["-v"], { encoding: "utf8" }).stdout.trim();
  console.error(`ERROR: This project supports Node 20-24 for Next.js development, but PATH has ${version}.`);
  console.error("Install Node 24, or set DEV_NODE to a Node 20-24 executable, then run npm run dev again.");
  process.exit(1);
}

const child = spawnSync(selectedNode, [nextBin, "dev", ...process.argv.slice(2)], {
  cwd: projectDir,
  stdio: "inherit",
});

process.exit(child.status ?? 1);
