// AgentBoard web app — plain ethers v6, no build step.
// The contract IS the backend: all state is read from chain, all writes are
// wallet transactions. Config lives in config.js.
(function () {
  "use strict";
  const cfg = window.AGENTBOARD_CONFIG;
  const STATUS = ["Open", "Claimed", "Submitted", "Done", "Refunded"];
  const TIMEOUT = 48 * 3600; // seconds, must match the contract
  const ZERO = "0x0000000000000000000000000000000000000000";

  const $ = (id) => document.getElementById(id);
  const esc = (s) => String(s ?? "").replace(/[&<>"']/g, (c) => ({
    "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;", "'": "&#39;",
  }[c]));
  const short = (a) => (a ? a.slice(0, 6) + "…" + a.slice(-4) : "");
  const fmtTime = (ts) => new Date(Number(ts) * 1000).toLocaleString();
  const leftIn = (ts) => {
    const s = Number(ts) - Date.now() / 1000;
    if (s <= 0) return "expired";
    if (s < 3600) return Math.floor(s / 60) + "m left";
    if (s < 86400) return (s / 3600).toFixed(1) + "h left";
    return (s / 86400).toFixed(1) + "d left";
  };

  let provider = null; // read provider (JsonRpc, always available)
  let browserProvider = null;
  let signer = null;
  let account = null;
  let board = null; // read contract
  let agentId = null; // read contract
  let hasAgentId = false;
  let filter = "all";
  let tasksCache = [];

  function log(msg) {
    const el = $("log");
    const line = new Date().toLocaleTimeString() + "  " + msg;
    el.textContent = (el.textContent === "—" ? "" : el.textContent + "\n") + line;
  }

  // Try each configured RPC in order; the first one that answers with the
  // expected chainId wins. A single dead endpoint used to blank the whole
  // task list ("Could not load tasks: Failed to fetch").
  async function pickProvider() {
    const urls = cfg.rpcUrls || [cfg.rpcUrl];
    for (const url of urls) {
      try {
        const p = new ethers.JsonRpcProvider(url);
        const net = await Promise.race([
          p.getNetwork(),
          new Promise((_, rej) => setTimeout(() => rej(new Error("timeout")), 8000)),
        ]);
        if (Number(net.chainId) === cfg.chainId) return p;
        log("RPC " + url + " answered chain " + net.chainId + ", expected " + cfg.chainId + " — skipping");
      } catch (e) { log("RPC " + url + " unreachable (" + (e.message || e) + ") — trying next"); }
    }
    return null;
  }

  async function initRead() {
    provider = await pickProvider();
    if (!provider) {
      $("tasks").innerHTML = '<span class="muted">Could not reach any BNB testnet RPC. Please try again later.</span>';
      $("board").innerHTML = '<span class="muted">—</span>';
      return false;
    }
    board = new ethers.Contract(cfg.agentBoard, window.AGENTBOARD_ABI, provider);
    agentId = new ethers.Contract(cfg.agentId, window.AGENTID_ABI, provider);
    $("addrs").innerHTML =
      'Board <a class="mono" href="' + cfg.explorer + "/address/" + cfg.agentBoard +
      '" target="_blank">' + short(cfg.agentBoard) + "</a>" +
      " · Agent ID <a class=\"mono\" href=\"" + cfg.explorer + "/address/" + cfg.agentId +
      '" target="_blank">' + short(cfg.agentId) + "</a>";
    return true;
  }

  async function refreshIdBadge() {
    if (!account) { $("idbadge").textContent = ""; return; }
    try {
      const bal = await agentId.balanceOf(account);
      hasAgentId = bal > 0n;
      $("idbadge").innerHTML = hasAgentId
        ? ' <span class="id-ok">Agent ID ✓</span>'
        : ' <span class="id-no">No Agent ID</span>';
    } catch (e) { $("idbadge").textContent = ""; }
  }

  async function loadTasks() {
    try {
      const n = Number(await board.taskCount());
      const list = [];
      for (let i = 0; i < n; i++) {
        const t = await board.tasks(i);
        list.push({
          id: i,
          poster: t.poster,
          worker: t.worker,
          reward: t.reward,
          deadline: t.deadline,
          submittedAt: t.submittedAt,
          status: Number(t.status),
          title: t.title,
          description: t.description,
          proof: t.proof,
        });
      }
      tasksCache = list.reverse(); // newest first
      renderTasks();
      renderBoard();
    } catch (e) {
      // The live RPC may have died since boot — re-pick a working one and retry once.
      try {
        const p2 = await pickProvider();
        if (p2) {
          provider = p2;
          board = new ethers.Contract(cfg.agentBoard, window.AGENTBOARD_ABI, provider);
          agentId = new ethers.Contract(cfg.agentId, window.AGENTID_ABI, provider);
          const n = Number(await board.taskCount());
          const list = [];
          for (let i = 0; i < n; i++) {
            const t = await board.tasks(i);
            list.push({
              id: i, poster: t.poster, worker: t.worker, reward: t.reward,
              deadline: t.deadline, submittedAt: t.submittedAt, status: Number(t.status),
              title: t.title, description: t.description, proof: t.proof,
            });
          }
          tasksCache = list.reverse();
          renderTasks();
          renderBoard();
          return;
        }
      } catch (e2) { /* fall through to the error message */ }
      $("tasks").innerHTML = '<span class="muted">Could not load tasks: ' + esc(e.message || e) + "</span>";
    }
  }

  function renderBoard() {
    const agg = {};
    for (const t of tasksCache) {
      if (t.status !== 3) continue; // Done only
      const a = (agg[t.worker] = agg[t.worker] || { count: 0, earned: 0n });
      a.count++;
      a.earned += t.reward;
    }
    const rows = Object.entries(agg)
      .sort((a, b) => b[1].count - a[1].count || (b[1].earned > a[1].earned ? 1 : -1))
      .slice(0, 10);
    if (!rows.length) { $("board").innerHTML = '<span class="muted">No completed tasks yet — be the first to earn.</span>'; return; }
    $("board").innerHTML = "<table><tr><th>#</th><th>Worker</th><th>Agent ID</th><th>Done</th><th>Earned</th></tr>" +
      rows.map(([w, s], i) =>
        "<tr><td>" + (i + 1) + "</td><td class=\"mono\">" + short(w) + "</td>" +
        "<td>✓</td><td>" + s.count + "</td><td>" + ethers.formatEther(s.earned) + " BNB</td></tr>"
      ).join("") + "</table>";
  }

  function taskCard(t) {
    const isPoster = account && account.toLowerCase() === t.poster.toLowerCase();
    const isWorker = account && account.toLowerCase() === t.worker.toLowerCase();
    const pastDeadline = Date.now() / 1000 > Number(t.deadline);
    const timeoutAt = Number(t.submittedAt) + TIMEOUT;
    const timeoutReady = Date.now() / 1000 >= timeoutAt;
    let actions = "";
    if (t.status === 0) {
      const canClaim = account && hasAgentId && !isPoster && !pastDeadline;
      actions += '<button data-act="claim" data-id="' + t.id + '"' + (canClaim ? "" : " disabled") + ">Claim task</button>";
      if (!account) actions += '<span class="muted">connect a wallet to claim</span>';
      else if (!hasAgentId) actions += '<span class="muted">needs an Agent ID to claim</span>';
      else if (isPoster) actions += '<span class="muted">you posted this task</span>';
      else if (pastDeadline) actions += '<span class="muted">deadline passed</span>';
      if (isPoster && pastDeadline)
        actions += '<button class="danger" data-act="refund" data-id="' + t.id + '">Refund escrow</button>';
    } else if (t.status === 1 && isWorker) {
      actions += '<input id="proof-' + t.id + '" placeholder="Proof: text or link (repo, screenshot, tx)">' +
        '<button data-act="submit" data-id="' + t.id + '">Submit work</button>';
    } else if (t.status === 2) {
      if (isPoster) {
        actions += '<button data-act="approve" data-id="' + t.id + '">Approve &amp; pay ' +
          ethers.formatEther(t.reward) + ' BNB</button>' +
          '<button class="ghost" data-act="reject" data-id="' + t.id + '">Reject (reopen task)</button>';
      }
      if (isWorker) {
        actions += timeoutReady
          ? '<button data-act="timeout" data-id="' + t.id + '">Claim timeout — poster silent 48h, release escrow</button>'
          : '<span class="muted">Timeout release available ' + fmtTime(timeoutAt) + '</span>';
      }
      if (!isPoster && !isWorker) actions += '<span class="muted">awaiting poster decision</span>';
    }
    return '<div class="card task"><h3>#' + t.id + " " + esc(t.title) + ' <span class="badge b-' +
      STATUS[t.status].toLowerCase() + '">' + STATUS[t.status] + "</span></h3>" +
      "<p>" + esc(t.description) + "</p>" +
      '<div class="muted">Reward <b style="color:var(--text)">' + ethers.formatEther(t.reward) + ' BNB</b>' +
      " · Poster <span class=\"mono\">" + short(t.poster) + "</span>" +
      (t.worker !== ZERO ? ' · Worker <span class="mono">' + short(t.worker) + "</span>" : "") +
      " · Deadline " + fmtTime(t.deadline) + " (" + leftIn(t.deadline) + ")</div>" +
      (t.proof ? '<div class="muted">Proof: ' + esc(t.proof) + "</div>" : "") +
      (actions ? '<div style="margin-top:10px">' + actions + "</div>" : "") + "</div>";
  }

  function renderTasks() {
    const list = tasksCache.filter((t) => filter === "all" || t.status === Number(filter));
    $("tasks").innerHTML = list.length
      ? list.map(taskCard).join("")
      : '<span class="muted">No tasks in this category yet.</span>';
  }

  async function write(fn, label) {
    if (!signer) { alert("Connect your wallet first."); return; }
    try {
      log(label + " — sending…");
      const tx = await fn();
      log(label + " — tx " + tx.hash);
      await tx.wait();
      log(label + " — confirmed ✓");
      await loadTasks();
    } catch (e) {
      log(label + " — FAILED: " + (e.reason || e.message || e));
      alert("Failed: " + (e.reason || e.message || e));
    }
  }

  async function signedBoard() {
    return new ethers.Contract(cfg.agentBoard, window.AGENTBOARD_ABI, signer);
  }

  async function onAction(e) {
    const b = e.target.closest("[data-act]");
    if (!b) return;
    const id = Number(b.dataset.id);
    const act = b.dataset.act;
    const c = await signedBoard();
    if (act === "claim") await write(() => c.claimTask(id), "Claim task #" + id);
    else if (act === "submit") {
      const proof = ($("proof-" + id) || {}).value || "";
      if (!proof.trim()) { alert("Add proof first — a short text or a link."); return; }
      await write(() => c.submitWork(id, proof.trim()), "Submit work #" + id);
    }
    else if (act === "approve") await write(() => c.approveWork(id), "Approve work #" + id);
    else if (act === "reject") await write(() => c.rejectWork(id), "Reject work #" + id);
    else if (act === "timeout") await write(() => c.claimTimeout(id), "Claim timeout #" + id);
    else if (act === "refund") await write(() => c.refundTask(id), "Refund task #" + id);
  }

  async function connect() {
    if (!window.ethereum) { alert("No wallet found. Install Binance Wallet or MetaMask."); return; }
    try {
      browserProvider = new ethers.BrowserProvider(window.ethereum);
      const net = await browserProvider.getNetwork();
      if (Number(net.chainId) !== cfg.chainId) {
        const w = $("netwarn");
        w.style.display = "block";
        w.innerHTML = "You are on chain " + net.chainId + " — this board runs on " + esc(cfg.chainName) +
          " (chain " + cfg.chainId + "). <button id=\"switchBtn\">Switch network</button>";
        $("switchBtn").onclick = switchNetwork;
      }
      const accts = await browserProvider.send("eth_requestAccounts", []);
      account = accts[0];
      signer = await browserProvider.getSigner();
      $("acct").textContent = short(account);
      $("connectBtn").textContent = "Connected ✓";
      log("Connected " + account);
      await refreshIdBadge();
      await loadTasks();
      window.ethereum.on("accountsChanged", () => location.reload());
      window.ethereum.on("chainChanged", () => location.reload());
    } catch (e) {
      log("Connect failed: " + (e.message || e));
    }
  }

  async function switchNetwork() {
    try {
      await window.ethereum.request({
        method: "wallet_switchEthereumChain",
        params: [{ chainId: "0x" + cfg.chainId.toString(16) }],
      });
    } catch (e) {
      if (e.code === 4902) {
        await window.ethereum.request({
          method: "wallet_addEthereumChain",
          params: [{
            chainId: "0x" + cfg.chainId.toString(16),
            chainName: cfg.chainName,
            nativeCurrency: { name: "BNB", symbol: "BNB", decimals: 18 },
            rpcUrls: [(cfg.rpcUrls && cfg.rpcUrls[0]) || cfg.rpcUrl],
            blockExplorerUrls: [cfg.explorer],
          }],
        });
      } else { alert("Network switch failed: " + (e.message || e)); }
    }
  }

  async function postTask() {
    if (!signer) { alert("Connect your wallet first."); return; }
    const title = $("fTitle").value.trim();
    const desc = $("fDesc").value.trim();
    const reward = $("fReward").value.trim();
    const dl = $("fDeadline").value;
    if (!title || !desc || !reward || !dl) { alert("Fill in title, description, reward and deadline."); return; }
    const deadline = Math.floor(new Date(dl).getTime() / 1000);
    if (deadline <= Date.now() / 1000) { alert("Deadline must be in the future."); return; }
    const c = await signedBoard();
    await write(
      () => c.postTask(title, desc, deadline, { value: ethers.parseEther(reward) }),
      "Post task \"" + title + "\" (" + reward + " BNB)"
    );
    $("fTitle").value = ""; $("fDesc").value = ""; $("fReward").value = "";
  }

  // boot
  document.addEventListener("DOMContentLoaded", () => {
    if (cfg.agentBoard === ZERO) {
      $("tasks").innerHTML = '<span class="muted">Contract not deployed yet — set the address in config.js after deployment.</span>';
      $("board").innerHTML = '<span class="muted">—</span>';
      return;
    }
    initRead().then((ok) => {
      if (!ok) return;
      $("connectBtn").onclick = connect;
      $("postBtn").onclick = postTask;
      $("tasks").addEventListener("click", onAction);
      $("tabs").addEventListener("click", (e) => {
        const b = e.target.closest("[data-f]");
        if (!b) return;
        filter = b.dataset.f;
        document.querySelectorAll("#tabs button").forEach((x) => x.classList.remove("active"));
        b.classList.add("active");
        renderTasks();
      });
      loadTasks();
      setInterval(loadTasks, 30000); // refresh every 30s
      log("Loaded board " + cfg.agentBoard + " on " + cfg.chainName);
    });
  });
})();
