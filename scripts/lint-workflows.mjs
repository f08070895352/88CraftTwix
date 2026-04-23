#!/usr/bin/env node
// n8n workflow JSON の静的チェック。
// - すべての node が { id, name, type, typeVersion, position, parameters } を持つ
// - connections の参照先ノードが実在する
// - IF/Set など、typeVersion に対する最低限のスキーマを確認
// - 同一 name の重複禁止

import { readFileSync, readdirSync } from "node:fs";
import { join, dirname } from "node:path";
import { fileURLToPath } from "node:url";

const here = dirname(fileURLToPath(import.meta.url));
const dir = join(here, "..", "workflows");

const REQUIRED_KEYS = ["id", "name", "type", "typeVersion", "position", "parameters"];

let errors = 0;
const fail = (file, msg) => {
  console.error(`✗ ${file}: ${msg}`);
  errors += 1;
};

for (const f of readdirSync(dir)) {
  if (!f.endsWith(".json")) continue;
  const path = join(dir, f);
  let wf;
  try {
    wf = JSON.parse(readFileSync(path, "utf8"));
  } catch (e) {
    fail(f, `invalid JSON: ${e.message}`);
    continue;
  }

  if (!Array.isArray(wf.nodes)) {
    fail(f, "nodes[] missing");
    continue;
  }
  if (typeof wf.connections !== "object") {
    fail(f, "connections{} missing");
    continue;
  }

  const names = new Set();
  const ids = new Set();
  for (const n of wf.nodes) {
    for (const k of REQUIRED_KEYS) {
      if (n[k] === undefined) fail(f, `node "${n.name || n.id}" missing ${k}`);
    }
    if (names.has(n.name)) fail(f, `duplicate node name: ${n.name}`);
    if (ids.has(n.id)) fail(f, `duplicate node id: ${n.id}`);
    names.add(n.name);
    ids.add(n.id);

    // IF v2 の conditions 構造
    if (n.type === "n8n-nodes-base.if" && n.typeVersion >= 2) {
      const conds = n.parameters?.conditions?.conditions;
      if (!Array.isArray(conds) || conds.length === 0) {
        fail(f, `IF "${n.name}" has no conditions`);
      } else {
        for (const c of conds) {
          if (!c.operator?.type || !c.operator?.operation) {
            fail(f, `IF "${n.name}" condition missing operator.type/operation`);
          }
        }
      }
    }

    // Set v3+ の assignments 構造
    if (n.type === "n8n-nodes-base.set" && n.typeVersion >= 3) {
      const a = n.parameters?.assignments?.assignments;
      if (!Array.isArray(a)) fail(f, `Set "${n.name}" missing assignments[]`);
      else {
        for (const as of a) {
          if (!as.name || !as.type) {
            fail(f, `Set "${n.name}" assignment missing name/type`);
          }
        }
      }
    }

    // HTTP Request v4+: authentication設定が無いのにcredentialType参照だと警告
    if (
      n.type === "n8n-nodes-base.httpRequest" &&
      n.parameters?.nodeCredentialType &&
      n.parameters?.authentication !== "predefinedCredentialType"
    ) {
      fail(f, `HTTP "${n.name}" uses nodeCredentialType but authentication != predefinedCredentialType`);
    }
  }

  // connections の参照整合性
  for (const [src, outs] of Object.entries(wf.connections)) {
    if (!names.has(src)) fail(f, `connection source "${src}" not in nodes`);
    for (const branch of outs.main || []) {
      for (const conn of branch) {
        if (!names.has(conn.node)) fail(f, `connection target "${conn.node}" not in nodes`);
      }
    }
  }

  console.log(`✓ ${f} (nodes=${wf.nodes.length})`);
}

if (errors > 0) {
  console.error(`\n${errors} error(s)`);
  process.exit(1);
}
console.log("\nall workflows pass static lint");
