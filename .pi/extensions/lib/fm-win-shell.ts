import { existsSync } from "node:fs";

// FirstMate's bin/*.sh scripts are spawned by direct path. On Windows a .sh file
// is not an executable image, and Node throws `spawn EFTYPE` synchronously for
// that error code (it is not in the deferred-to-'error'-event list), which
// crashes the calling hook before any error handler can swallow it. Route the
// script through Git bash instead so the same call sites work on all platforms.
const GIT_BASH_CANDIDATES = [
  "C:\\Program Files\\Git\\usr\\bin\\bash.exe",
  "C:\\Program Files\\Git\\bin\\bash.exe",
  "C:\\Program Files (x86)\\Git\\usr\\bin\\bash.exe",
  "C:\\Program Files (x86)\\Git\\bin\\bash.exe",
];

let cachedBash: string | undefined;

function gitBash(): string {
  if (cachedBash === undefined) {
    cachedBash = GIT_BASH_CANDIDATES.find((candidate) => existsSync(candidate)) ?? "bash.exe";
  }
  return cachedBash;
}

export function shellScriptInvocation(
  script: string,
  args: string[] = [],
): { file: string; args: string[] } {
  if (process.platform === "win32") {
    return { file: gitBash(), args: [script, ...args] };
  }
  return { file: script, args };
}
