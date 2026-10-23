// The Node side of `node_jolt.dart`: instantiates `jolt.wasm`, then answers one
// JSON request per line.
//
//   node jolt_host.mjs <jolt.wasm> <request-fifo> <response-fifo>
//
// Requests are `{"f": "<export>", "a": [...]}` for a function call or
// `{"m": "<memory op>", "a": [...]}` for a memory access; replies are
// `{"r": value}` or `{"e": message}`.
import fs from 'node:fs';

const [wasmPath, requestPath, responsePath] = process.argv.slice(2);
if (!wasmPath || !requestPath || !responsePath) {
  console.error('usage: jolt_host.mjs <jolt.wasm> <request-fifo> <response-fifo>');
  process.exit(2);
}

const bytes = fs.readFileSync(wasmPath);
const { instance } = await WebAssembly.instantiate(bytes, {});
const exports = instance.exports;
exports._initialize();

const requests = fs.openSync(requestPath, 'r');
const responses = fs.openSync(responsePath, 'w');

const memoryOp = (op, args) => {
  const view = new DataView(exports.memory.buffer);
  switch (op) {
    case 'w64':
      view.setFloat64(args[0], args[1], true);
      return 0;
    case 'w32f':
      view.setFloat32(args[0], args[1], true);
      return 0;
    case 'w32':
      view.setUint32(args[0], args[1], true);
      return 0;
    case 'r32f':
      return view.getFloat32(args[0], true);
    case 'r32':
      return view.getUint32(args[0], true);
    default:
      throw new Error(`unknown memory op ${op}`);
  }
};

let pending = Buffer.alloc(0);
const chunk = Buffer.alloc(1 << 16);

for (;;) {
  const read = fs.readSync(requests, chunk, 0, chunk.length, null);
  if (read === 0) break;
  pending = Buffer.concat([pending, chunk.subarray(0, read)]);

  let newline;
  while ((newline = pending.indexOf(0x0a)) >= 0) {
    const line = pending.subarray(0, newline).toString('utf8');
    pending = pending.subarray(newline + 1);
    if (line.length === 0) continue;

    let reply;
    try {
      const message = JSON.parse(line);
      let result;
      if (message.m !== undefined) {
        result = memoryOp(message.m, message.a ?? []);
      } else {
        const fn = exports[message.f];
        if (typeof fn !== 'function') {
          throw new Error(`no export ${message.f}`);
        }
        result = fn(...(message.a ?? []));
      }
      reply = { r: result === undefined ? 0 : result };
    } catch (error) {
      reply = { e: String(error) };
    }
    fs.writeSync(responses, `${JSON.stringify(reply)}\n`);
  }
}

fs.closeSync(requests);
fs.closeSync(responses);
