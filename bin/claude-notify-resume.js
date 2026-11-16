#!/usr/bin/env node
// Installs claude-notify-resume into Claude Code, or updates it if it is
// already installed.
//
//   npx @anaidenko/claude-notify-resume
//   npx @anaidenko/claude-notify-resume --help
//
// It runs the same `claude plugin` commands the README lists, so the plugin
// still comes from the anaidenko marketplace (git), never from this package.
// That keeps one delivery path for installed copies, whichever way they were
// first installed.
//
// This is NOT a hook. The hooks follow the repo's one rule: never break the
// session, so every failure exits 0 silently. This file runs once, by hand, and
// a failure nobody sees is a failure nobody fixes. Here every failure exits
// non-zero and says why. Do not "align" it with the hooks.
'use strict';

const { spawnSync } = require('node:child_process');
const fs = require('node:fs');
const path = require('node:path');

const MARKETPLACE = 'anaidenko';
const MARKETPLACE_REPO = 'anaidenko/claude-plugins';
const PLUGIN_ID = 'claude-notify-resume@anaidenko';
const README = 'https://github.com/anaidenko/claude-notify-resume#readme';

function fail(message) {
    process.stderr.write(`\n${message}\n`);
    process.exit(1);
}

function usage() {
    process.stdout.write(`Usage: npx @anaidenko/claude-notify-resume

Installs the claude-notify-resume plugin into Claude Code, or updates it if it
is already installed. It adds the ${MARKETPLACE_REPO} marketplace when
missing, then runs \`claude plugin install\` (or \`update\`).

Details: ${README}
`);
}

// Runs `claude <args> --json` and returns the parsed output.
function claudeJson(args) {
    const r = spawnSync('claude', [...args, '--json'], { encoding: 'utf8' });
    if (r.error && r.error.code === 'ENOENT') {
        fail('Claude Code CLI (`claude`) not found on PATH.\n' +
            'Install Claude Code first: https://code.claude.com/docs\n' +
            'Then run this again.');
    }
    if (r.error || r.status !== 0) {
        fail(`\`claude ${args.join(' ')} --json\` failed:\n${(r.stderr || '').trim()}`);
    }
    try {
        return JSON.parse(r.stdout);
    } catch {
        fail(`Could not read the output of \`claude ${args.join(' ')} --json\`.\n` +
            'Your Claude Code may be too old for this installer; run the two\n' +
            `commands from ${README} instead.`);
    }
}

// Runs a mutating `claude` command in the open, so its own output shows.
function claude(args) {
    process.stdout.write(`\n$ claude ${args.join(' ')}\n`);
    const r = spawnSync('claude', args, { stdio: 'inherit' });
    if (r.error || r.status !== 0) {
        fail(`\`claude ${args.join(' ')}\` failed (exit ${r.status ?? r.error.code}).`);
    }
}

// True when the marketplace entry is ours, however it was added: the GitHub
// shorthand reports `repo`, a git URL reports `url`.
function isOurs(entry) {
    const repo = String(entry.repo || '').toLowerCase();
    const url = String(entry.url || '').toLowerCase();
    return repo === MARKETPLACE_REPO ||
        /github\.com[/:]anaidenko\/claude-plugins(\.git)?\/?$/.test(url);
}

function describe(entry) {
    return entry.repo || entry.url || entry.path || `a ${entry.source || 'different'} source`;
}

function onPath(cmd) {
    const dirs = (process.env.PATH || '').split(path.delimiter);
    // Homebrew's prefixes: the hook finds the notifier there even when the
    // shell running this installer has them off PATH.
    dirs.push('/opt/homebrew/bin', '/usr/local/bin');
    return dirs.some(d => d && fs.existsSync(path.join(d, cmd)));
}

function main() {
    const args = process.argv.slice(2);
    if (args.includes('--help') || args.includes('-h')) {
        usage();
        return;
    }
    if (args.length > 0) {
        usage();
        process.exit(1);
    }

    if (process.platform === 'win32') {
        fail('claude-notify-resume supports macOS and Linux only; Windows has no\n' +
            `notification path yet. See ${README}`);
    }

    const marketplaces = claudeJson(['plugin', 'marketplace', 'list']);
    const entry = Array.isArray(marketplaces) && marketplaces.find(m => m.name === MARKETPLACE);

    if (!entry) {
        claude(['plugin', 'marketplace', 'add', MARKETPLACE_REPO]);
    } else if (!isOurs(entry)) {
        // Early installs used the plugin's own repo as the marketplace. That
        // repo no longer carries a marketplace.json, so such an entry is dead,
        // but removing a user's marketplace can take its plugins with it.
        // That is their call, not this script's.
        fail(`A marketplace named "${MARKETPLACE}" already exists, but it points at\n` +
            `${describe(entry)}, not ${MARKETPLACE_REPO}. It is most likely left over\n` +
            'from an older install. To replace it, run:\n\n' +
            `  claude plugin marketplace remove ${MARKETPLACE}\n` +
            `  claude plugin marketplace add ${MARKETPLACE_REPO}\n\n` +
            'and then run this installer again.');
    } else {
        claude(['plugin', 'marketplace', 'update', MARKETPLACE]);
    }

    const plugins = claudeJson(['plugin', 'list']);
    const installed = Array.isArray(plugins) && plugins.some(p => p.id === PLUGIN_ID);

    claude(['plugin', installed ? 'update' : 'install', PLUGIN_ID]);

    const next = ['Restart Claude Code to load the hooks: hook config is read at startup.'];
    if (process.platform === 'darwin' && !onPath('terminal-notifier')) {
        next.push('For click-to-resume on macOS: brew install terminal-notifier');
    }
    if (process.platform === 'linux' && !onPath('notify-send')) {
        next.push('Banners need notify-send: sudo apt install libnotify-bin (or your distro\'s package)');
    }
    // `claude plugin update` succeeds whether or not there was anything newer,
    // so claim only what is true either way.
    const done = installed ? `${PLUGIN_ID} is installed and up to date.` : `Installed ${PLUGIN_ID}.`;
    process.stdout.write(`\n${done}\n` +
        next.map(line => `  - ${line}`).join('\n') + `\n\nMore: ${README}\n`);
}

main();
