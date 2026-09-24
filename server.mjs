import { createHash } from "node:crypto";
import { execFile } from "node:child_process";
import { copyFile, mkdir, realpath, readdir, readFile, rename as renamePath, rm, stat, writeFile } from "node:fs/promises";
import path from "node:path";
import readline from "node:readline";
import { fileURLToPath } from "node:url";
import { promisify } from "node:util";

const configuredRoot = path.resolve(process.env.LOCAL_OPS_ROOT || process.cwd());
const root = await realpath(configuredRoot);
const maxBytes = Number.parseInt(process.env.LOCAL_OPS_MAX_BYTES || "2097152", 10);
const execFileAsync = promisify(execFile);
const gitTimeoutMs = Number.parseInt(process.env.LOCAL_OPS_GIT_TIMEOUT_MS || "30000", 10);
const gitRemoteTimeoutMs = Number.parseInt(process.env.LOCAL_OPS_GIT_REMOTE_TIMEOUT_MS || "60000", 10);

function booleanEnv(name, defaultValue) {
  const value = process.env[name];
  if (value === undefined || value === "") return defaultValue;
  if (["1", "true", "yes", "on"].includes(value.toLowerCase())) return true;
  if (["0", "false", "no", "off"].includes(value.toLowerCase())) return false;
  throw new Error(`${name} must be true or false`);
}

const gitReadEnabled = booleanEnv("LOCAL_OPS_GIT_READ", true);
const gitWriteEnabled = booleanEnv("LOCAL_OPS_GIT_WRITE", true);
const gitRemoteEnabled = booleanEnv("LOCAL_OPS_GIT_REMOTE", false);
const gitFetchEnabled = booleanEnv("LOCAL_OPS_GIT_FETCH", true);
const gitPullEnabled = booleanEnv("LOCAL_OPS_GIT_PULL", false);
const gitPushEnabled = booleanEnv("LOCAL_OPS_GIT_PUSH", false);

function isInsideRoot(candidate) {
  const relative = path.relative(root, candidate);
  return relative === "" || (!relative.startsWith("..") && !path.isAbsolute(relative));
}

async function resolveExisting(relativePath) {
  if (typeof relativePath !== "string" || relativePath.includes("\0")) {
    throw new Error("path must be a valid string");
  }
  const lexical = path.resolve(root, relativePath || ".");
  if (!isInsideRoot(lexical)) throw new Error("path is outside LOCAL_OPS_ROOT");
  const actual = await realpath(lexical);
  if (!isInsideRoot(actual)) throw new Error("resolved path is outside LOCAL_OPS_ROOT");
  return actual;
}

async function resolveWritable(relativePath) {
  if (typeof relativePath !== "string" || !relativePath || relativePath.includes("\0")) {
    throw new Error("path must be a non-empty valid string");
  }
  const lexical = path.resolve(root, relativePath);
  if (!isInsideRoot(lexical)) throw new Error("path is outside LOCAL_OPS_ROOT");
  const parent = await realpath(path.dirname(lexical));
  if (!isInsideRoot(parent)) throw new Error("parent resolves outside LOCAL_OPS_ROOT");
  try {
    const actual = await realpath(lexical);
    if (!isInsideRoot(actual)) throw new Error("existing path resolves outside LOCAL_OPS_ROOT");
  } catch (error) {
    if (error?.code !== "ENOENT") throw error;
  }
  return lexical;
}

async function resolveNewFileDestination(relativePath) {
  const destination = await resolveWritable(relativePath);
  try {
    await stat(destination);
    throw new Error("destination already exists");
  } catch (error) {
    if (error?.code !== "ENOENT") throw error;
  }
  return destination;
}

async function resolveCreatableDirectory(relativePath) {
  if (typeof relativePath !== "string" || !relativePath || relativePath.includes("\0")) {
    throw new Error("path must be a non-empty valid string");
  }
  const lexical = path.resolve(root, relativePath);
  if (!isInsideRoot(lexical)) throw new Error("path is outside LOCAL_OPS_ROOT");
  let existingAncestor = lexical;
  while (true) {
    try {
      existingAncestor = await realpath(existingAncestor);
      break;
    } catch (error) {
      if (error?.code !== "ENOENT") throw error;
      const parent = path.dirname(existingAncestor);
      if (parent === existingAncestor) throw error;
      existingAncestor = parent;
    }
  }
  if (!isInsideRoot(existingAncestor)) throw new Error("ancestor resolves outside LOCAL_OPS_ROOT");
  return lexical;
}

function sha256(buffer) {
  return createHash("sha256").update(buffer).digest("hex");
}

function textResult(text) {
  return { content: [{ type: "text", text }] };
}

async function runGit(cwd, args, remoteOperation = false) {
  const disabledHooksPath = process.platform === "win32" ? "NUL" : "/dev/null";
  try {
    const { stdout, stderr } = await execFileAsync("git", [
      "-C", cwd,
      "-c", `core.hooksPath=${disabledHooksPath}`,
      "-c", "core.fsmonitor=false",
      "-c", "commit.gpgSign=false",
      ...args
    ], {
      encoding: "utf8",
      env: remoteOperation
        ? { ...process.env, GIT_TERMINAL_PROMPT: "0", GCM_INTERACTIVE: "Never" }
        : process.env,
      maxBuffer: maxBytes,
      timeout: remoteOperation ? gitRemoteTimeoutMs : gitTimeoutMs,
      windowsHide: true
    });
    return `${stdout}${stderr}`.trim() || "(no output)";
  } catch (error) {
    if (error?.code === "ENOENT") throw new Error("git executable was not found on PATH");
    if (error?.killed) throw new Error(`git command exceeded ${remoteOperation ? gitRemoteTimeoutMs : gitTimeoutMs} ms timeout`);
    const detail = `${error?.stdout || ""}${error?.stderr || ""}`.trim();
    throw new Error(detail || error?.message || "git command failed");
  }
}

function validateRemoteName(remote) {
  if (typeof remote !== "string" || !remote || remote.startsWith("-") || remote.includes("\0") || /[\r\n]/.test(remote)) {
    throw new Error("remote name is invalid");
  }
  return remote;
}

async function validateRemote(repository, remote) {
  const name = validateRemoteName(remote);
  const remotes = (await runGit(repository, ["remote"]))
    .split(/\r?\n/)
    .filter((entry) => entry && entry !== "(no output)");
  if (!remotes.includes(name)) throw new Error(`Git remote does not exist: ${name}`);
  const url = await runGit(repository, ["remote", "get-url", "--push", name]);
  if (/^(https?|ssh|git):\/\//i.test(url) || /^[^@\s/:]+@[^:\s]+:.+/.test(url)) return name;

  let localPath;
  try {
    localPath = url.startsWith("file://") ? fileURLToPath(url) : path.resolve(repository, url);
  } catch {
    throw new Error("remote URL must use http(s), ssh, git, or an allowed local path");
  }
  const actual = await realpath(localPath);
  if (!isInsideRoot(actual)) throw new Error("local Git remote is outside LOCAL_OPS_ROOT");
  return name;
}

async function currentUpstream(repository) {
  const branch = await runGit(repository, ["symbolic-ref", "--quiet", "--short", "HEAD"]);
  const remote = await runGit(repository, ["config", "--get", `branch.${branch}.remote`]);
  const mergeRef = await runGit(repository, ["config", "--get", `branch.${branch}.merge`]);
  if (remote === "." || !mergeRef.startsWith("refs/heads/") || /[\r\n\0]/.test(mergeRef)) {
    throw new Error("current branch does not have a supported remote upstream");
  }
  await validateRemote(repository, remote);
  return { branch, remote, mergeRef };
}

async function resolveRepository(relativePath = ".") {
  const directory = await resolveExisting(relativePath);
  if (!(await stat(directory)).isDirectory()) throw new Error("repo_path is not a directory");
  const topLevel = await runGit(directory, ["rev-parse", "--show-toplevel"]);
  const repository = await realpath(topLevel);
  if (!isInsideRoot(repository)) throw new Error("repository is outside LOCAL_OPS_ROOT");
  return repository;
}

function validatePositiveInteger(value, name, defaultValue, maximum) {
  if (value === undefined) return defaultValue;
  if (!Number.isInteger(value) || value < 1 || value > maximum) {
    throw new Error(`${name} must be an integer between 1 and ${maximum}`);
  }
  return value;
}

function validateRevision(revision) {
  if (typeof revision !== "string" || !revision || revision.startsWith("-") || revision.includes("\0")) {
    throw new Error("revision must be a non-empty Git revision and cannot start with -");
  }
  return revision;
}

function validateGitPaths(repository, files) {
  if (!Array.isArray(files) || files.length === 0) throw new Error("files must be a non-empty array");
  return files.map((file) => {
    if (typeof file !== "string" || !file || file.includes("\0") || path.isAbsolute(file)) {
      throw new Error("each file must be a non-empty repository-relative path");
    }
    const candidate = path.resolve(repository, file);
    const relative = path.relative(repository, candidate);
    if (relative.startsWith("..") || path.isAbsolute(relative)) throw new Error("file is outside the repository");
    return relative || ".";
  });
}

const allTools = [
  {
    name: "list_directory",
    description: "List files and directories below the configured local workspace root.",
    inputSchema: {
      type: "object",
      properties: { path: { type: "string", description: "Workspace-relative directory path; defaults to ." } },
      additionalProperties: false
    },
    annotations: { readOnlyHint: true, destructiveHint: false }
  },
  {
    name: "read_file",
    description: "Read a UTF-8 text file below the configured workspace root and return its SHA-256 hash.",
    inputSchema: {
      type: "object",
      properties: { path: { type: "string", description: "Workspace-relative file path" } },
      required: ["path"],
      additionalProperties: false
    },
    annotations: { readOnlyHint: true, destructiveHint: false }
  },
  {
    name: "write_file",
    description: "Write a UTF-8 text file below the configured workspace root. Existing files require overwrite=true; expected_sha256 can prevent lost updates.",
    inputSchema: {
      type: "object",
      properties: {
        path: { type: "string", description: "Workspace-relative file path; parent directory must already exist" },
        content: { type: "string", description: "Complete UTF-8 file contents" },
        overwrite: { type: "boolean", default: false },
        expected_sha256: { type: "string", description: "Optional SHA-256 of the existing file returned by read_file" }
      },
      required: ["path", "content"],
      additionalProperties: false
    },
    annotations: { readOnlyHint: false, destructiveHint: true }
  },
  {
    name: "create_directory",
    description: "Create a directory below the configured workspace root. Set recursive=true to also create missing parent directories.",
    inputSchema: {
      type: "object",
      properties: {
        path: { type: "string", description: "Workspace-relative directory path" },
        recursive: { type: "boolean", default: false, description: "Also create missing parent directories" }
      },
      required: ["path"],
      additionalProperties: false
    },
    annotations: { readOnlyHint: false, destructiveHint: false }
  },
  {
    name: "delete_directory",
    description: "Delete a directory below the configured workspace root. Non-empty directories require recursive=true. The workspace root itself can never be deleted.",
    inputSchema: {
      type: "object",
      properties: {
        path: { type: "string", description: "Workspace-relative directory path" },
        recursive: { type: "boolean", default: false, description: "Delete the directory and all of its contents" }
      },
      required: ["path"],
      additionalProperties: false
    },
    annotations: { readOnlyHint: false, destructiveHint: true }
  },
  {
    name: "delete_file",
    description: "Delete a regular file below the configured workspace root.",
    inputSchema: {
      type: "object",
      properties: { path: { type: "string", description: "Workspace-relative file path" } },
      required: ["path"],
      additionalProperties: false
    },
    annotations: { readOnlyHint: false, destructiveHint: true }
  },
  {
    name: "copy_file",
    description: "Copy a regular file within the configured workspace root. Existing destinations require overwrite=true.",
    inputSchema: {
      type: "object",
      properties: {
        source: { type: "string", description: "Workspace-relative source file path" },
        destination: { type: "string", description: "Workspace-relative destination file path; parent directory must exist" },
        overwrite: { type: "boolean", default: false }
      },
      required: ["source", "destination"],
      additionalProperties: false
    },
    annotations: { readOnlyHint: false, destructiveHint: true }
  },
  {
    name: "move_file",
    description: "Move a regular file to a new workspace-relative path. The destination must not already exist.",
    inputSchema: {
      type: "object",
      properties: {
        source: { type: "string", description: "Workspace-relative source file path" },
        destination: { type: "string", description: "Workspace-relative destination file path; parent directory must exist" }
      },
      required: ["source", "destination"],
      additionalProperties: false
    },
    annotations: { readOnlyHint: false, destructiveHint: true }
  },
  {
    name: "move_directory",
    description: "Move a directory and all of its contents to a new workspace-relative path. The destination must not already exist and cannot be inside the source directory.",
    inputSchema: {
      type: "object",
      properties: {
        source: { type: "string", description: "Workspace-relative source directory path; the workspace root cannot be moved" },
        destination: { type: "string", description: "Workspace-relative destination directory path; parent directory must exist" }
      },
      required: ["source", "destination"],
      additionalProperties: false
    },
    annotations: { readOnlyHint: false, destructiveHint: true }
  },
  {
    name: "rename_file",
    description: "Rename a regular file without moving it to another directory. The new name must not already exist.",
    inputSchema: {
      type: "object",
      properties: {
        path: { type: "string", description: "Workspace-relative source file path" },
        new_name: { type: "string", description: "New file name only, without directory components" }
      },
      required: ["path", "new_name"],
      additionalProperties: false
    },
    annotations: { readOnlyHint: false, destructiveHint: true }
  },
  {
    name: "git_status",
    description: "Show the concise Git working-tree status for a repository below the configured workspace root.",
    inputSchema: {
      type: "object",
      properties: { repo_path: { type: "string", description: "Workspace-relative repository path; defaults to ." } },
      additionalProperties: false
    },
    annotations: { readOnlyHint: true, destructiveHint: false }
  },
  {
    name: "git_diff_unstaged",
    description: "Show unstaged Git changes for a repository below the configured workspace root.",
    inputSchema: {
      type: "object",
      properties: { repo_path: { type: "string", description: "Workspace-relative repository path; defaults to ." } },
      additionalProperties: false
    },
    annotations: { readOnlyHint: true, destructiveHint: false }
  },
  {
    name: "git_diff_staged",
    description: "Show staged Git changes for a repository below the configured workspace root.",
    inputSchema: {
      type: "object",
      properties: { repo_path: { type: "string", description: "Workspace-relative repository path; defaults to ." } },
      additionalProperties: false
    },
    annotations: { readOnlyHint: true, destructiveHint: false }
  },
  {
    name: "git_log",
    description: "Show recent Git commits for a repository below the configured workspace root.",
    inputSchema: {
      type: "object",
      properties: {
        repo_path: { type: "string", description: "Workspace-relative repository path; defaults to ." },
        max_count: { type: "integer", minimum: 1, maximum: 100, default: 10 }
      },
      additionalProperties: false
    },
    annotations: { readOnlyHint: true, destructiveHint: false }
  },
  {
    name: "git_show",
    description: "Show one Git revision without invoking external diff helpers.",
    inputSchema: {
      type: "object",
      properties: {
        repo_path: { type: "string", description: "Workspace-relative repository path; defaults to ." },
        revision: { type: "string", description: "Commit, tag, or branch name; cannot start with -" }
      },
      required: ["revision"],
      additionalProperties: false
    },
    annotations: { readOnlyHint: true, destructiveHint: false }
  },
  {
    name: "git_branch",
    description: "List local, remote, or all Git branches.",
    inputSchema: {
      type: "object",
      properties: {
        repo_path: { type: "string", description: "Workspace-relative repository path; defaults to ." },
        branch_type: { type: "string", enum: ["local", "remote", "all"], default: "local" }
      },
      additionalProperties: false
    },
    annotations: { readOnlyHint: true, destructiveHint: false }
  },
  {
    name: "git_add",
    description: "Stage an explicit list of repository-relative files. Arbitrary Git options are not accepted.",
    inputSchema: {
      type: "object",
      properties: {
        repo_path: { type: "string", description: "Workspace-relative repository path; defaults to ." },
        files: { type: "array", minItems: 1, items: { type: "string" } }
      },
      required: ["files"],
      additionalProperties: false
    },
    annotations: { readOnlyHint: false, destructiveHint: false }
  },
  {
    name: "git_commit",
    description: "Create a local Git commit from already staged changes. This does not stage files or contact a remote.",
    inputSchema: {
      type: "object",
      properties: {
        repo_path: { type: "string", description: "Workspace-relative repository path; defaults to ." },
        message: { type: "string", minLength: 1, maxLength: 10000 }
      },
      required: ["message"],
      additionalProperties: false
    },
    annotations: { readOnlyHint: false, destructiveHint: false }
  },
  {
    name: "git_amend_message",
    description: "Rewrite only the most recent local commit message without including staged or working-tree changes. This rewrites local history and does not contact a remote.",
    inputSchema: {
      type: "object",
      properties: {
        repo_path: { type: "string", description: "Workspace-relative repository path; defaults to ." },
        message: { type: "string", minLength: 1, maxLength: 10000 }
      },
      required: ["message"],
      additionalProperties: false
    },
    annotations: { readOnlyHint: false, destructiveHint: true }
  },
  {
    name: "git_fetch",
    description: "Fetch branches from an existing configured Git remote without fetching tags. Requires both the remote and fetch switches.",
    inputSchema: {
      type: "object",
      properties: {
        repo_path: { type: "string", description: "Workspace-relative repository path; defaults to ." },
        remote: { type: "string", default: "origin", description: "Existing configured remote name; defaults to origin" }
      },
      additionalProperties: false
    },
    annotations: { readOnlyHint: false, destructiveHint: false, openWorldHint: true }
  },
  {
    name: "git_pull",
    description: "Fast-forward the current branch from its configured upstream. Diverged branches stop without merging.",
    inputSchema: {
      type: "object",
      properties: { repo_path: { type: "string", description: "Workspace-relative repository path; defaults to ." } },
      additionalProperties: false
    },
    annotations: { readOnlyHint: false, destructiveHint: true, openWorldHint: true }
  },
  {
    name: "git_push",
    description: "Push only the current branch to its configured upstream using a non-force refspec. Force push and remote deletion are not supported.",
    inputSchema: {
      type: "object",
      properties: { repo_path: { type: "string", description: "Workspace-relative repository path; defaults to ." } },
      additionalProperties: false
    },
    annotations: { readOnlyHint: false, destructiveHint: true, openWorldHint: true }
  }
];

const gitReadTools = new Set(["git_status", "git_diff_unstaged", "git_diff_staged", "git_log", "git_show", "git_branch"]);
const gitWriteTools = new Set(["git_add", "git_commit", "git_amend_message"]);
const gitRemoteTools = new Set(["git_fetch", "git_pull", "git_push"]);
const tools = allTools.filter((tool) => {
  if (gitReadTools.has(tool.name)) return gitReadEnabled;
  if (gitWriteTools.has(tool.name)) return gitWriteEnabled;
  if (!gitRemoteTools.has(tool.name)) return true;
  if (!gitRemoteEnabled) return false;
  if (tool.name === "git_fetch") return gitFetchEnabled;
  if (tool.name === "git_pull") return gitPullEnabled;
  if (tool.name === "git_push") return gitPushEnabled;
  return false;
});

async function callTool(name, args = {}) {
  if (!tools.some((tool) => tool.name === name)) throw new Error(`tool is disabled or unknown: ${name}`);
  if (name === "list_directory") {
    const directory = await resolveExisting(args.path || ".");
    if (!(await stat(directory)).isDirectory()) throw new Error("path is not a directory");
    const entries = await readdir(directory, { withFileTypes: true });
    const rows = entries
      .map((entry) => `${entry.isDirectory() ? "directory" : entry.isFile() ? "file" : "other"}\t${entry.name}`)
      .sort((a, b) => a.localeCompare(b));
    return textResult(rows.join("\n") || "(empty directory)");
  }

  if (name === "read_file") {
    const file = await resolveExisting(args.path);
    const info = await stat(file);
    if (!info.isFile()) throw new Error("path is not a regular file");
    if (info.size > maxBytes) throw new Error(`file exceeds ${maxBytes} byte limit`);
    const data = await readFile(file);
    return textResult(`sha256:${sha256(data)}\n${data.toString("utf8")}`);
  }

  if (name === "write_file") {
    if (typeof args.content !== "string") throw new Error("content must be a string");
    const data = Buffer.from(args.content, "utf8");
    if (data.byteLength > maxBytes) throw new Error(`content exceeds ${maxBytes} byte limit`);
    const file = await resolveWritable(args.path);
    let existing = null;
    try {
      existing = await readFile(file);
    } catch (error) {
      if (error?.code !== "ENOENT") throw error;
    }
    if (existing && !args.overwrite) throw new Error("file exists; set overwrite=true to replace it");
    if (args.expected_sha256 && (!existing || sha256(existing) !== args.expected_sha256)) {
      throw new Error("expected_sha256 does not match the current file");
    }
    await writeFile(file, data, { flag: existing ? "w" : "wx" });
    return textResult(`wrote ${data.byteLength} bytes to ${path.relative(root, file)}\nsha256:${sha256(data)}`);
  }

  if (name === "create_directory") {
    const directory = args.recursive === true
      ? await resolveCreatableDirectory(args.path)
      : await resolveWritable(args.path);
    await mkdir(directory, { recursive: args.recursive === true });
    return textResult(`created directory ${path.relative(root, directory)}`);
  }

  if (name === "delete_directory") {
    const directory = await resolveExisting(args.path);
    if (directory === root) throw new Error("workspace root cannot be deleted");
    if (!(await stat(directory)).isDirectory()) throw new Error("path is not a directory");
    await rm(directory, { recursive: args.recursive === true, force: false });
    return textResult(`deleted directory ${path.relative(root, directory)}`);
  }

  if (name === "delete_file") {
    const file = await resolveExisting(args.path);
    if (!(await stat(file)).isFile()) throw new Error("path is not a regular file");
    await rm(file, { force: false });
    return textResult(`deleted file ${path.relative(root, file)}`);
  }

  if (name === "copy_file") {
    const source = await resolveExisting(args.source);
    if (!(await stat(source)).isFile()) throw new Error("source is not a regular file");
    const destination = await resolveWritable(args.destination);
    if (source === destination) throw new Error("source and destination must be different");
    let destinationExists = false;
    try {
      destinationExists = (await stat(destination)).isFile();
      if (!destinationExists) throw new Error("destination is not a regular file");
    } catch (error) {
      if (error?.code !== "ENOENT") throw error;
    }
    if (destinationExists && args.overwrite !== true) {
      throw new Error("destination exists; set overwrite=true to replace it");
    }
    await copyFile(source, destination);
    return textResult(`copied ${path.relative(root, source)} to ${path.relative(root, destination)}`);
  }

  if (name === "move_file") {
    const source = await resolveExisting(args.source);
    if (!(await stat(source)).isFile()) throw new Error("source is not a regular file");
    const destination = await resolveNewFileDestination(args.destination);
    if (source === destination) throw new Error("source and destination must be different");
    await renamePath(source, destination);
    return textResult(`moved ${path.relative(root, source)} to ${path.relative(root, destination)}`);
  }

  if (name === "move_directory") {
    const source = await resolveExisting(args.source);
    if (source === root) throw new Error("workspace root cannot be moved");
    if (!(await stat(source)).isDirectory()) throw new Error("source is not a directory");
    const destination = await resolveNewFileDestination(args.destination);
    const relativeDestination = path.relative(source, destination);
    if (relativeDestination && !relativeDestination.startsWith("..") && !path.isAbsolute(relativeDestination)) {
      throw new Error("destination cannot be inside the source directory");
    }
    await renamePath(source, destination);
    return textResult(`moved directory ${path.relative(root, source)} to ${path.relative(root, destination)}`);
  }

  if (name === "rename_file") {
    if (typeof args.new_name !== "string" || !args.new_name || args.new_name.includes("\0") || path.basename(args.new_name) !== args.new_name || args.new_name === "." || args.new_name === "..") {
      throw new Error("new_name must be a valid file name without directory components");
    }
    const source = await resolveExisting(args.path);
    if (!(await stat(source)).isFile()) throw new Error("path is not a regular file");
    const destination = await resolveNewFileDestination(path.join(path.dirname(path.relative(root, source)), args.new_name));
    await renamePath(source, destination);
    return textResult(`renamed ${path.relative(root, source)} to ${path.relative(root, destination)}`);
  }

  if (name === "git_status") {
    const repository = await resolveRepository(args.repo_path);
    return textResult(await runGit(repository, ["status", "--short", "--branch"]));
  }

  if (name === "git_diff_unstaged") {
    const repository = await resolveRepository(args.repo_path);
    return textResult(await runGit(repository, ["--no-pager", "diff", "--no-ext-diff", "--no-textconv", "--"]));
  }

  if (name === "git_diff_staged") {
    const repository = await resolveRepository(args.repo_path);
    return textResult(await runGit(repository, ["--no-pager", "diff", "--cached", "--no-ext-diff", "--no-textconv", "--"]));
  }

  if (name === "git_log") {
    const repository = await resolveRepository(args.repo_path);
    const maxCount = validatePositiveInteger(args.max_count, "max_count", 10, 100);
    return textResult(await runGit(repository, ["--no-pager", "log", `--max-count=${maxCount}`, "--date=iso-strict", "--pretty=format:%H%x09%aI%x09%an%x09%s"]));
  }

  if (name === "git_show") {
    const repository = await resolveRepository(args.repo_path);
    const revision = validateRevision(args.revision);
    return textResult(await runGit(repository, ["--no-pager", "show", "--no-ext-diff", "--no-textconv", "--format=fuller", "--end-of-options", revision]));
  }

  if (name === "git_branch") {
    const repository = await resolveRepository(args.repo_path);
    const branchType = args.branch_type || "local";
    if (!["local", "remote", "all"].includes(branchType)) throw new Error("branch_type must be local, remote, or all");
    const flag = branchType === "remote" ? "--remotes" : branchType === "all" ? "--all" : "--list";
    return textResult(await runGit(repository, ["--no-pager", "branch", flag, "--no-color"]));
  }

  if (name === "git_add") {
    const repository = await resolveRepository(args.repo_path);
    const files = validateGitPaths(repository, args.files);
    await runGit(repository, ["add", "--", ...files]);
    return textResult(`staged ${files.length} path(s):\n${files.join("\n")}`);
  }

  if (name === "git_commit") {
    if (typeof args.message !== "string" || !args.message.trim()) throw new Error("message must be a non-empty string");
    if (args.message.length > 10000 || args.message.includes("\0")) throw new Error("message exceeds limits or contains an invalid character");
    const repository = await resolveRepository(args.repo_path);
    return textResult(await runGit(repository, ["commit", "--message", args.message]));
  }

  if (name === "git_amend_message") {
    if (typeof args.message !== "string" || !args.message.trim()) throw new Error("message must be a non-empty string");
    if (args.message.length > 10000 || args.message.includes("\0")) throw new Error("message exceeds limits or contains an invalid character");
    const repository = await resolveRepository(args.repo_path);
    return textResult(await runGit(repository, ["commit", "--amend", "--only", "--message", args.message]));
  }

  if (name === "git_fetch") {
    const repository = await resolveRepository(args.repo_path);
    const remote = await validateRemote(repository, args.remote || "origin");
    return textResult(await runGit(repository, ["fetch", "--no-tags", remote], true));
  }

  if (name === "git_pull") {
    const repository = await resolveRepository(args.repo_path);
    const { remote, mergeRef } = await currentUpstream(repository);
    return textResult(await runGit(repository, ["pull", "--ff-only", "--no-tags", remote, mergeRef], true));
  }

  if (name === "git_push") {
    const repository = await resolveRepository(args.repo_path);
    const { branch, remote, mergeRef } = await currentUpstream(repository);
    const result = await runGit(repository, ["push", "--porcelain", remote, `HEAD:${mergeRef}`], true);
    return textResult(`pushed ${branch} to ${remote}/${mergeRef.slice("refs/heads/".length)}\n${result}`);
  }

  throw new Error(`unknown tool: ${name}`);
}

function send(payload) {
  process.stdout.write(`${JSON.stringify(payload)}\n`);
}

async function handle(message) {
  if (!message || message.jsonrpc !== "2.0" || typeof message.method !== "string") return;
  if (message.id === undefined) return;
  try {
    let result;
    if (message.method === "initialize") {
      result = {
        protocolVersion: message.params?.protocolVersion || "2025-06-18",
        capabilities: { tools: { listChanged: false } },
        serverInfo: { name: "local-ops-mcp", version: "0.3.0" },
        instructions: `Only access files under ${root}. Read before overwriting. Use expected_sha256 when updating an existing file.`
      };
    } else if (message.method === "tools/list") {
      result = { tools };
    } else if (message.method === "tools/call") {
      result = await callTool(message.params?.name, message.params?.arguments || {});
    } else if (message.method === "ping") {
      result = {};
    } else {
      send({ jsonrpc: "2.0", id: message.id, error: { code: -32601, message: "Method not found" } });
      return;
    }
    send({ jsonrpc: "2.0", id: message.id, result });
  } catch (error) {
    const messageText = error instanceof Error ? error.message : String(error);
    if (message.method === "tools/call") {
      send({ jsonrpc: "2.0", id: message.id, result: { isError: true, content: [{ type: "text", text: messageText }] } });
    } else {
      send({ jsonrpc: "2.0", id: message.id, error: { code: -32603, message: messageText } });
    }
  }
}

console.error(`local-ops-mcp root: ${root}`);
const input = readline.createInterface({ input: process.stdin, crlfDelay: Infinity, terminal: false });
for await (const line of input) {
  if (!line.trim()) continue;
  try {
    await handle(JSON.parse(line));
  } catch (error) {
    console.error(`invalid MCP message: ${error instanceof Error ? error.message : String(error)}`);
  }
}
