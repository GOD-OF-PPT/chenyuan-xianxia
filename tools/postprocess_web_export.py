#!/usr/bin/env python3
"""
Post-process Godot 4.3 Web WASM export in builds/web/:
1. Split index.wasm and index.pck into <1.5 MiB chunks (+ pre-gzipped .gz for WASM) so remote reverse proxies with 16MB/32MB body limits never truncate or stall.
2. Inject sandboxed-iframe IndexedDB/localStorage getter shields and synthetic-stream WebAssembly.instantiate fallback into index.html with live progress bar.
"""
import gzip
import json
import os
import shutil

REPO_ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), ".."))
WEB_DIR = os.path.join(REPO_ROOT, "builds/web")
CHUNKS_DIR = os.path.join(WEB_DIR, "chunks")
CHUNK_SIZE = 1536 * 1024  # 1.5 MiB

HTML_TEMPLATE = """<!DOCTYPE html>
<html lang="zh-CN">
	<head>
		<meta charset="utf-8">
		<meta name="viewport" content="width=device-width, user-scalable=no, initial-scale=1.0">
		<title>尘缘问道 · 第一章青岚境</title>
		<style>
html, body, #canvas {
	margin: 0;
	padding: 0;
	border: 0;
}

body {
	color: #E5DDD0;
	background-color: #161514;
	overflow: hidden;
	touch-action: none;
	font-family: "Noto Serif SC", "Songti SC", "Microsoft YaHei", serif;
}

#canvas {
	display: block;
}

#canvas:focus {
	outline: none;
}

#status {
	position: absolute;
	inset: 0;
	background: radial-gradient(circle at center, #23201D 0%, #141210 100%);
	display: flex;
	flex-direction: column;
	justify-content: center;
	align-items: center;
	gap: 16px;
	z-index: 10;
}

#status-title {
	font-size: 32px;
	color: #D6A85A;
	letter-spacing: 4px;
	font-weight: bold;
}

#status-sub {
	font-size: 16px;
	color: #9EE0C4;
}

#status-bar-bg {
	width: min(520px, 78vw);
	height: 14px;
	background: #1C1917;
	border: 1px solid #7D6339;
	border-radius: 4px;
	overflow: hidden;
}

#status-bar-fill {
	width: 2%;
	height: 100%;
	background: linear-gradient(90deg, #3E7B67 0%, #D6A85A 100%);
	transition: width 0.15s ease-out;
}

#status-detail {
	font-size: 15px;
	color: #C9C0B2;
}

#status-notice {
	display: none;
	background-color: #4A201E;
	border-radius: 6px;
	border: 1px solid #D6A85A;
	color: #F4ECE1;
	line-height: 1.5;
	max-width: 680px;
	margin: 8px 24px;
	padding: 14px 20px;
	text-align: center;
	white-space: pre-wrap;
}
		</style>
		<link id="-gd-engine-icon" rel="icon" type="image/png" href="index.icon.png" />
		<link rel="apple-touch-icon" href="index.apple-touch-icon.png"/>
	</head>
	<body>
		<canvas id="canvas">
			您的浏览器不支持 HTML5 Canvas。
		</canvas>

		<div id="status">
			<div id="status-title">《尘缘问道》</div>
			<div id="status-sub">第一卷 · 山雨欲来风满楼（青岚境 v0.1.5-slice 试玩版）</div>
			<div id="status-bar-bg"><div id="status-bar-fill"></div></div>
			<div id="status-detail">正在连接云端画卷分片...</div>
			<div id="status-notice"></div>
		</div>

		<script>
(function shieldSandboxAPIs() {
	let idbGetterOk = false;
	try {
		const idb = window.indexedDB;
		if (idb && typeof idb.open === 'function') {
			idbGetterOk = true;
		}
	} catch (_e) {
		try {
			Object.defineProperty(window, 'indexedDB', { value: undefined, configurable: true });
		} catch (_e2) {}
	}
	for (const k of ['localStorage', 'sessionStorage']) {
		try {
			void window[k];
		} catch (_e) {
			const mem = {};
			try {
				Object.defineProperty(window, k, {
					configurable: true,
					value: {
						getItem: (p) => (p in mem ? mem[p] : null),
						setItem: (p, v) => { mem[p] = String(v); },
						removeItem: (p) => { delete mem[p]; },
						clear: () => { for (const x in mem) delete mem[x]; },
					},
				});
			} catch (_e2) {}
		}
	}
	window.__IDB_GETTER_OK__ = idbGetterOk;
})();

(function patchWasmStreamingFallback() {
	if (typeof WebAssembly !== 'undefined' && typeof WebAssembly.instantiateStreaming === 'function') {
		const nativeStreaming = WebAssembly.instantiateStreaming.bind(WebAssembly);
		WebAssembly.instantiateStreaming = async function (source, importObject) {
			const resp = await source;
			let fallbackBufPromise = null;
			try {
				fallbackBufPromise = resp.clone().arrayBuffer();
			} catch (_e) {}
			try {
				return await nativeStreaming(resp, importObject);
			} catch (_streamErr) {
				const buf = fallbackBufPromise ? await fallbackBufPromise : await resp.arrayBuffer();
				return await WebAssembly.instantiate(buf, importObject);
			}
		};
	}
})();

(function installChunkedFetch() {
	const origFetch = window.fetch.bind(window);
	let manifestPromise = null;
	const chunkProgress = { doneChunks: 0, totalChunks: __TOTAL_CHUNKS__, bytesLoaded: 0 };

	window.__updateBootBanner = function (msg, pct) {
		const det = document.getElementById('status-detail');
		const fill = document.getElementById('status-bar-fill');
		if (det) det.textContent = msg;
		if (fill && typeof pct === 'number') {
			fill.style.width = Math.max(2, Math.min(100, pct)).toFixed(1) + '%';
		}
	};

	function getManifest() {
		if (!manifestPromise) {
			manifestPromise = origFetch('chunk_manifest.json?t=' + Date.now()).then((r) => {
				if (!r.ok) throw new Error('chunk_manifest HTTP ' + r.status);
				return r.json();
			});
		}
		return manifestPromise;
	}

	async function gunzipBuffer(gzArrayBuffer) {
		const ds = new DecompressionStream('gzip');
		const stream = new Blob([gzArrayBuffer]).stream().pipeThrough(ds);
		return await new Response(stream).arrayBuffer();
	}

	async function fetchOneChunk(part, preferGz) {
		const useGz = preferGz && typeof DecompressionStream !== 'undefined' && part.gz_size < part.size * 0.75;
		const url = (useGz ? (part.url + '.gz') : part.url) + '?b=__BUILD_TAG__';
		for (let attempt = 1; attempt <= 4; attempt++) {
			try {
				const resp = await origFetch(url);
				if (!resp.ok) throw new Error('HTTP ' + resp.status + ' on ' + url);
				const buf = await resp.arrayBuffer();
				const rawBuf = useGz ? await gunzipBuffer(buf) : buf;
				chunkProgress.doneChunks += 1;
				chunkProgress.bytesLoaded += buf.byteLength;
				const pct = (chunkProgress.doneChunks / Math.max(1, chunkProgress.totalChunks)) * 92;
				window.__updateBootBanner(
					`正在载入引擎与青岚画卷：${Math.round(pct)}%（分片 ${chunkProgress.doneChunks}/${chunkProgress.totalChunks} · 已传输 ${(chunkProgress.bytesLoaded / 1048576).toFixed(1)} MB）`,
					pct
				);
				return new Uint8Array(rawBuf);
			} catch (err) {
				if (attempt === 4) throw err;
				await new Promise((res) => setTimeout(res, 400 * attempt));
			}
		}
	}

	async function fetchChunkedAsset(assetName, entry, totalManifestChunks) {
		chunkProgress.totalChunks = totalManifestChunks;
		const parts = entry.parts;
		const results = new Array(parts.length);
		const preferGz = assetName.endsWith('.wasm');
		let cursor = 0;
		const concurrency = 6;

		async function worker() {
			while (cursor < parts.length) {
				const idx = cursor++;
				results[idx] = await fetchOneChunk(parts[idx], preferGz);
			}
		}

		const workers = [];
		for (let i = 0; i < Math.min(concurrency, parts.length); i++) {
			workers.push(worker());
		}
		await Promise.all(workers);

		const merged = new Uint8Array(entry.total_size);
		let offset = 0;
		for (let i = 0; i < results.length; i++) {
			merged.set(results[i], offset);
			offset += results[i].byteLength;
			results[i] = null;
		}

		return new Response(merged, {
			status: 200,
			headers: {
				'Content-Type': entry.mime,
				'Content-Length': String(merged.byteLength),
			},
		});
	}

	window.fetch = function (input, init) {
		const urlStr = typeof input === 'string' ? input : (input && input.url ? input.url : '');
		const cleanName = urlStr.split('?')[0].split('/').pop();
		if (cleanName === 'index.wasm' || cleanName === 'index.pck') {
			return getManifest().then((manifest) => {
				const entry = manifest[cleanName];
				if (!entry) return origFetch(input, init);
				const totalC = Object.values(manifest).reduce((acc, v) => acc + v.parts.length, 0);
				return fetchChunkedAsset(cleanName, entry, totalC);
			});
		}
		return origFetch(input, init);
	};
})();
		</script>
		<script src="index.js?b=__BUILD_TAG__"></script>
		<script>
async function probeIndexedDBAvailable() {
	if (!window.__IDB_GETTER_OK__) return false;
	return new Promise((resolve) => {
		let settled = false;
		const finish = (ok) => {
			if (!settled) {
				settled = true;
				resolve(ok);
			}
		};
		const timer = setTimeout(() => finish(false), 350);
		try {
			const req = window.indexedDB.open('__chenyuan_idb_probe__', 1);
			req.onsuccess = () => {
				clearTimeout(timer);
				try { req.result.close(); } catch (_e) {}
				finish(true);
			};
			req.onerror = () => {
				clearTimeout(timer);
				finish(false);
			};
			req.onblocked = () => {
				clearTimeout(timer);
				finish(false);
			};
		} catch (_err) {
			clearTimeout(timer);
			finish(false);
		}
	});
}

async function probeWasmCspAllowed() {
	try {
		const minimalWasm = new Uint8Array([0x00, 0x61, 0x73, 0x6d, 0x01, 0x00, 0x00, 0x00]);
		await WebAssembly.compile(minimalWasm);
		return { ok: true, err: null };
	} catch (err) {
		return { ok: false, err };
	}
}

(async function bootChenyuan() {
	const statusOverlay = document.getElementById('status');
	const statusNotice = document.getElementById('status-notice');
	const statusBarBg = document.getElementById('status-bar-bg');
	const statusDetail = document.getElementById('status-detail');

	function showCspOpenInBrowserGuide() {
		if (statusBarBg) statusBarBg.style.display = 'none';
		if (statusDetail) statusDetail.textContent = '检测到当前内置预览小窗限制了 WebAssembly 引擎运行';
		if (statusNotice) {
			statusNotice.style.display = 'block';
			statusNotice.style.backgroundColor = '#1F1B17';
			statusNotice.innerHTML = '';

			const p1 = document.createElement('div');
			p1.style.fontSize = '17px';
			p1.style.color = '#F4ECE1';
			p1.style.marginBottom = '12px';
			p1.textContent = '编辑器内嵌预览沙盒默认未开放 WebAssembly 编译权限（wasm-unsafe-eval），需在独立浏览器标签页中运行：';
			statusNotice.appendChild(p1);

			if (window.location && /^https?:$/i.test(window.location.protocol)) {
				const btn = document.createElement('a');
				btn.href = window.location.href;
				btn.target = '_blank';
				btn.rel = 'noopener noreferrer';
				btn.textContent = '▶ 点击在新浏览器标签页全屏启动《尘缘问道》 ↗';
				btn.style.display = 'inline-block';
				btn.style.margin = '6px 0 14px 0';
				btn.style.padding = '10px 22px';
				btn.style.background = '#3E7B67';
				btn.style.border = '1px solid #D6A85A';
				btn.style.borderRadius = '5px';
				btn.style.color = '#FFF8EC';
				btn.style.fontSize = '17px';
				btn.style.fontWeight = 'bold';
				btn.style.textDecoration = 'none';
				statusNotice.appendChild(btn);
			}

			const p2 = document.createElement('div');
			p2.style.fontSize = '15px';
			p2.style.color = '#D6A85A';
			p2.textContent = '操作提示：请直接点击上方按钮，或点击预览窗右上角工具栏的【在浏览器中打开 / Open in Browser (↗)】图标即可全速畅玩。';
			statusNotice.appendChild(p2);
		}
	}

	function displayFailureNotice(err) {
		console.error(err);
		const msg = err && err.message ? err.message : String(err);
		if (/Content Security Policy|unsafe-eval|WebAssembly/i.test(msg)) {
			showCspOpenInBrowserGuide();
			return;
		}
		if (statusNotice) {
			statusNotice.style.display = 'block';
			statusNotice.textContent = '启动异常：' + msg;
		}
	}

	window.addEventListener('unhandledrejection', (ev) => {
		displayFailureNotice(ev.reason || 'Unhandled Promise Rejection');
	});

	const wasmProbe = await probeWasmCspAllowed();
	if (!wasmProbe.ok) {
		showCspOpenInBrowserGuide();
		return;
	}

	const idbOk = await probeIndexedDBAvailable();
	const GODOT_CONFIG = {
		"args": [],
		"canvasResizePolicy": 2,
		"ensureCrossOriginIsolationHeaders": false,
		"executable": "index",
		"experimentalVK": false,
		"fileSizes": {"index.pck": __PCK_SIZE__, "index.wasm": __WASM_SIZE__},
		"focusCanvas": true,
		"gdextensionLibs": [],
		"persistentPaths": idbOk ? ["/userfs"] : []
	};

	const missing = Engine.getMissingFeatures({ threads: false });
	if (missing.length !== 0) {
		displayFailureNotice('浏览器缺少运行所需特性：\\n' + missing.join('\\n'));
		return;
	}

	const engine = new Engine(GODOT_CONFIG);
	engine.startGame({
		'onProgress': function (current, total) {
			if (current > 0 && total > 0 && current >= total) {
				window.__updateBootBanner('正在初始化水墨渲染管线（最后一步）...', 98);
			}
		},
	}).then(() => {
		if (statusOverlay) statusOverlay.remove();
	}, displayFailureNotice);
})();
		</script>
	</body>
</html>
"""


def main() -> None:
    if os.path.exists(CHUNKS_DIR):
        shutil.rmtree(CHUNKS_DIR)
    os.makedirs(CHUNKS_DIR, exist_ok=True)

    manifest = {}
    for fname in ["index.wasm", "index.pck"]:
        src = os.path.join(WEB_DIR, fname)
        data = open(src, "rb").read()
        parts = []
        idx = 0
        for offset in range(0, len(data), CHUNK_SIZE):
            piece = data[offset : offset + CHUNK_SIZE]
            part_name = f"{fname}.{idx:03d}.bin"
            raw_path = os.path.join(CHUNKS_DIR, part_name)
            with open(raw_path, "wb") as rf:
                rf.write(piece)
            gz_bytes = gzip.compress(piece, compresslevel=6)
            if fname.endswith(".wasm"):
                with open(raw_path + ".gz", "wb") as gf:
                    gf.write(gz_bytes)
            parts.append({"url": f"chunks/{part_name}", "size": len(piece), "gz_size": len(gz_bytes)})
            idx += 1
        manifest[fname] = {
            "total_size": len(data),
            "mime": "application/wasm" if fname.endswith(".wasm") else "application/octet-stream",
            "parts": parts,
        }

    with open(os.path.join(WEB_DIR, "chunk_manifest.json"), "w", encoding="utf-8") as mf:
        json.dump(manifest, mf)

    import hashlib
    pck_hash = hashlib.sha256(open(os.path.join(WEB_DIR, "index.pck"), "rb").read()).hexdigest()[:8]
    total_chunks = sum(len(v["parts"]) for v in manifest.values())
    html_out = (
        HTML_TEMPLATE.replace("__TOTAL_CHUNKS__", str(total_chunks))
        .replace("__PCK_SIZE__", str(manifest["index.pck"]["total_size"]))
        .replace("__WASM_SIZE__", str(manifest["index.wasm"]["total_size"]))
        .replace("__BUILD_TAG__", pck_hash)
    )
    with open(os.path.join(WEB_DIR, "index.html"), "w", encoding="utf-8") as hf:
        hf.write(html_out)

    print(f"Web post-process complete: {total_chunks} chunks (build={pck_hash}) generated & sandbox-safe index.html written.")


if __name__ == "__main__":
    main()
