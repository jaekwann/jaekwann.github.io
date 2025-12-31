<!DOCTYPE html>
<html>
<head>
<meta charset="UTF-8">
<title>Perfect Renju (Fixed AI & UI)</title>
<style>
    body {
        background-color: #f0f0f0;
        font-family: 'Segoe UI', Tahoma, Geneva, Verdana, sans-serif;
        margin: 0;
        padding: 20px;
        display: flex;
        justify-content: center;
        align-items: center;
        min-height: 100vh;
    }
    #game_container {
        text-align: center;
        background: #fff;
        padding: 30px;
        border-radius: 15px;
        box-shadow: 0 10px 25px rgba(0,0,0,0.1);
        max-width: 720px;
        width: 100%;
    }
    h1 {
        color: #333;
        margin: 0 0 20px 0;
        letter-spacing: 2px;
        font-size: 32px;
        font-weight: 300;
        text-transform: uppercase;
    }
    .status-bar {
        display: flex;
        justify-content: space-between;
        align-items: center;
        background: #f8f9fa;
        padding: 10px 20px;
        border-radius: 8px;
        margin-bottom: 20px;
        border: 1px solid #eee;
        color: #555;
        font-size: 14px;
    }
    canvas {
        cursor: crosshair;
        border-radius: 4px;
        box-shadow: 2px 2px 8px rgba(0,0,0,0.3);
    }
    #v_status {
        margin-top: 15px;
        font-size: 18px;
        font-weight: 600;
        color: #333;
        min-height: 24px;
    }
    #v_forbidden {
        margin-top: 5px;
        font-size: 14px;
        color: #e74c3c;
        font-weight: bold;
        min-height: 20px;
    }
    .btn-group {
        margin-top: 20px;
        display: flex;
        justify-content: center;
        gap: 10px;
        flex-wrap: wrap;
    }
    button {
        padding: 10px 20px;
        font-size: 14px;
        font-weight: 600;
        border: none;
        border-radius: 6px;
        cursor: pointer;
        transition: 0.2s;
    }
    button:hover { opacity: 0.9; transform: translateY(-1px); }
    button:active { transform: translateY(0); }
    
    .btn-swap { background: #6c757d; color: white; }
    .btn-reset { background: #28a745; color: white; }
    .btn-undo { background: #ffc107; color: #333; }
    .btn-hint { background: #17a2b8; color: white; }
</style>
</head>
<body>

    <div id="game_container">
        <h1>Perfect Renju</h1>
        
        <div class="status-bar">
            <div style="text-align: left;">
                <div>👤 <b>YOU:</b> <span id="u_role" style="color:#000; font-weight:bold;">흑 (선수)</span></div>
                <div>🤖 <b>AI:</b> <span id="a_role" style="color:#888; font-weight:bold;">백 (후수)</span></div>
            </div>
            <div id="v_stats" style="text-align: right; color: #888;">
                <div>MODE: <b id="s_mode">READY</b></div>
                <div>CALC: <b id="s_nodes">0</b> | DEPTH: <b id="s_depth">0</b></div>
            </div>
        </div>

        <div style="position: relative; display: inline-block;">
            <canvas id="vBoard" width="600" height="600"></canvas>
        </div>

        <div id="v_status">준비 완료</div>
        <div id="v_forbidden"></div>
        
        <div class="btn-group">
            <button class="btn-swap" onclick="swapSides()">🔄 흑백 교환</button>
            <button class="btn-reset" onclick="resetVoid()">🚀 새 게임</button>
            <button class="btn-undo" onclick="undoMove()">↶ 무르기</button>
            <button class="btn-hint" onclick="requestHint()">💡힌트</button>
        </div>
    </div>

    <script>
    (function() {
        // ==========================================
        // [AI WORKER CODE] - Powerful Logic + Fixed Jumped 4 Detection
        // ==========================================
        const workerSource = `
        const INF = 1000000000; 
        let nodes = 0; let mctsSims = 0; let startTime = 0;
        const TIME_LIMIT = 1000; const MAX_TT_SIZE = 5000000; 
        
        // Basic Opening Book (Center only)
        const BOOK = { "": {r:7, c:7} }; 

        const POS_WEIGHTS = new Int32Array(225);
        for(let r=0; r<15; r++) for(let c=0; c<15; c++) {
            let d = Math.sqrt((r-7)*(r-7) + (c-7)*(c-7));
            POS_WEIGHTS[r*15+c] = Math.round(100 * Math.exp(-d/5)) * 10; 
        }
        const ZOBRIST = [new BigUint64Array(225), new BigUint64Array(225)];
        {
            let seed = 0xDEADBEEFn;
            function rand() { seed = (seed * 6364136223846793005n + 1442695040888963407n); return seed; }
            for(let p=0; p<2; p++) for(let i=0; i<225; i++) ZOBRIST[p][i] = rand();
        }
        let TT = new Map();
        let KILLER = Array.from({length: 60}, () => [null, null]);
        let HISTORY = [new Int32Array(225), new Int32Array(225)];
        let MCTS_SCORES = new Int32Array(225); 
        const DIRECTIONS = [1n, 15n, 16n, 14n]; 
        
        self.onmessage = function(e) {
            const d = e.data; 
            try {
                if (d.type === 'RESET') { 
                    TT.clear(); KILLER = Array.from({length: 60}, () => [null, null]);
                    HISTORY = [new Int32Array(225), new Int32Array(225)];
                    MCTS_SCORES.fill(0); return; 
                }
                
                const b = BigInt(d.b); const w = BigInt(d.w); const turn = d.turn;
                let currentHash = computeHash(b, w);
                let initScoreB = evalFull(b, w);
                let initScoreW = evalFull(w, b);

                if (d.type === 'HINT') {
                    startTime = Date.now();
                    const res = runPVS(b, w, turn, currentHash, 800, initScoreB, initScoreW); 
                    self.postMessage({ type: 'HINT_RESULT', move: res.move });
                    return;
                }
                
                if (d.type === 'THINK') {
                    nodes = 0; cutoffs = 0; mctsSims = 0; startTime = Date.now(); MCTS_SCORES.fill(0);
                    if (d.history === "") { self.postMessage({ type: 'RESULT', move: {r:7,c:7}, nodes: 1, depth: 'BOOK', note: 'Start' }); return; }

                    // 1. Force Win (VCF) / Force Block
                    let winSeq = solveVCF(b, w, turn, 0, []);
                    if (winSeq) { self.postMessage({ type: 'RESULT', move: winSeq[0], nodes, depth: 'VCF', note: 'VCF WIN' }); return; }
                    let vctSeq = solveVCT(b, w, turn, 0, []);
                    if (vctSeq) { self.postMessage({ type: 'RESULT', move: vctSeq[0], nodes, depth: 'VCT', note: 'VCT FOUND' }); return; }

                    // 2. MCTS for positioning
                    const stoneCount = countStones(b|w);
                    let mctsTime = (stoneCount < 180) ? (stoneCount < 10 ? TIME_LIMIT * 0.4 : TIME_LIMIT * 0.1) : 0;
                    if (mctsTime > 0) runMCTS(b, w, turn, mctsTime);

                    // 3. PVS Search
                    const result = runPVS(b, w, turn, currentHash, TIME_LIMIT, initScoreB, initScoreW);
                    if (!result || !result.move) throw "No move found";
                    self.postMessage({ type: 'RESULT', move: result.move, nodes, score: result.val, depth: result.depth, note: 'GM ENGINE' });
                }
            } catch (err) {
                // Recovery logic
                const fb_b = BigInt(e.data.b); const fb_w = BigInt(e.data.w);
                let fallbackMoves = getRankedCands(fb_b, fb_w, e.data.turn, 0, null, true);
                self.postMessage({ type: 'RESULT', move: fallbackMoves[0], nodes: nodes, depth: 'ERR', note: 'RECOVERY' });
            }
        };

        function countStones(occ) { let c=0; for(let i=0; i<225; i++) if((occ>>BigInt(i))&1n) c++; return c; }
        function computeHash(b, w) {
            let h = 0n; for(let i=0; i<225; i++) { if((b>>BigInt(i))&1n) h^=ZOBRIST[0][i]; if((w>>BigInt(i))&1n) h^=ZOBRIST[1][i]; } return h;
        }

        // --- MCTS Logic (Simplifed) ---
        class MCTSNode { constructor(p,m,t){this.parent=p;this.move=m;this.turn=t;this.wins=0;this.visits=0;this.children=[];this.untried=[];this.isTerminal=false;}}
        function runMCTS(b,w,rt,tb){
            let root=new MCTSNode(null,null,rt);
            let cands=getRankedCands(b,w,rt,0,null,true).slice(0,30);
            for(let c of cands)root.untried.push(c);
            let et=Date.now()+tb;
            while(Date.now()<et){
                let n=root; let cb=b,cw=w; let ct=rt;
                while(n.untried.length===0&&n.children.length>0){
                    n=uctSelect(n); let p=BigInt(n.move.r*15+n.move.c);
                    if(n.parent.turn===1)cb|=(1n<<p);else cw|=(1n<<p); ct=3-n.parent.turn;
                }
                if(n.untried.length>0){
                    let m=n.untried.pop(); let p=BigInt(m.r*15+m.c);
                    if(n.turn===1&&isForbidden(cb|(1n<<p),cw,p)){
                         n.isTerminal=true; n.wins=-1000;
                    }else{
                        let c=new MCTSNode(n,m,3-n.turn); n.children.push(c); n=c;
                        if(n.parent.turn===1)cb|=(1n<<p);else cw|=(1n<<p); ct=3-n.parent.turn;
                        if(checkWin(ct===2?cb:cw,p)) n.isTerminal=true;
                        else {
                            let nc=getRankedCands(cb,cw,ct,0,null,true).slice(0,10); for(let cc of nc)n.untried.push(cc);
                        }
                    }
                }
                let res=0;
                if(!n.isTerminal) res=runPatternSimulation(cb,cw,ct);
                else { if(n.wins<-500)res=2; else res=3-n.turn; }
                while(n){ n.visits++; if(res===(3-n.turn))n.wins++; else if(res===n.turn)n.wins--; n=n.parent; }
            }
            for(let c of root.children){ MCTS_SCORES[c.move.r*15+c.move.c] = (c.wins/c.visits)*3000+(c.visits*20); }
        }
        function uctSelect(n){ let b=null,bs=-1e9; for(let c of n.children){ let s=(c.wins/c.visits)+1.41*Math.sqrt(Math.log(n.visits)/c.visits); if(s>bs){bs=s;b=c;}} return b; }
        function runPatternSimulation(b,w,t){
             let cb=b,cw=w,ct=t,s=0;
             while(s<30){
                 let wm=findWinMove(cb,cw,ct); if(wm)return ct;
                 let ms=getRankedCands(cb,cw,ct,70,null,true).slice(0,4); if(ms.length===0)return 3;
                 let bm=ms[0]; if(Math.random()>0.7&&ms.length>1)bm=ms[1];
                 let p=BigInt(bm.r*15+bm.c);
                 if(ct===1&&isForbidden(cb|(1n<<p),cw,p))return 2;
                 if(ct===1)cb|=(1n<<p);else cw|=(1n<<p); ct=3-ct; s++;
             }
             return 3;
        }

        // --- PVS & Search ---
        function storeKiller(depth, move) {
            if (KILLER[depth][0] && KILLER[depth][0].r === move.r && KILLER[depth][0].c === move.c) return;
            KILLER[depth][1] = KILLER[depth][0]; KILLER[depth][0] = move;
        }

        function runPVS(b, w, turn, hash, limit, scoreB, scoreW) {
            let cands = getRankedCands(b, w, turn, 0, null, false);
            let bestMove = cands.length > 0 ? cands[0] : {r:7, c:7};
            
            // Check immediate threats
            for (let m of cands) {
                 let p = BigInt(m.r * 15 + m.c);
                 if (turn === 1 && isForbidden(b | (1n << p), w, p)) continue;
                 let nb = turn===1?b|(1n<<p):b; let nw = turn===2?w|(1n<<p):w;
                 if (checkWin(turn===1?nb:nw, p)) return { move: m, depth: 1, val: 999999 };
            }

            let maxD = 0; let previousScore = 0; let window = 25000; 
            for (let d = 2; d <= 20; d++) {
                 maxD = d; let alpha = -INF; let beta = INF;
                 if (d >= 4) { alpha = previousScore - window; beta = previousScore + window; }
                 let score = pvsRoot(b, w, turn, d, alpha, beta, hash, limit, scoreB, scoreW);
                 if (score.val <= alpha || score.val >= beta) {
                     window = 5000000; 
                     if (Date.now() - startTime < limit) score = pvsRoot(b, w, turn, d, -INF, INF, hash, limit, scoreB, scoreW);
                 } else { window = Math.max(10000, window - 5000); }
                 if (Date.now() - startTime > limit) break;
                 previousScore = score.val; if (score.move) bestMove = score.move;
                 for(let p=0; p<2; p++) for(let i=0; i<225; i++) HISTORY[p][i] = (HISTORY[p][i] * 0.9) >> 0; 
            }
            return { move: bestMove, depth: maxD, val: previousScore };
        }

        function pvsRoot(b, w, turn, depth, alpha, beta, hash, limit, scB, scW) {
             let rootMoves = getRankedCands(b, w, turn, depth, null, true); 
             if (rootMoves.length === 0) return {val: 0, move: {r:7, c:7}};
             let bestScore = -INF; let bestMove = null;
             for (let i = 0; i < rootMoves.length; i++) {
                if (Date.now() - startTime > limit) break;
                let m = rootMoves[i]; let pos = BigInt(m.r * 15 + m.c);
                if (turn === 1 && isForbidden(b | (1n << pos), w, pos)) continue;
                if (!bestMove) bestMove = m;
                let nextHash = hash ^ ZOBRIST[turn-1][m.r*15 + m.c];
                let nb = turn === 1 ? b | (1n << pos) : b; let nw = turn === 2 ? w | (1n << pos) : w;
                let deltaB = evalMoveUltra(nb, nw, b, w, m.r, m.c, 1);
                let deltaW = evalMoveUltra(nw, nb, w, b, m.r, m.c, 2); 
                let score;
                if (i === 0) score = -pvs(nb, nw, 3 - turn, depth - 1, -beta, -alpha, nextHash, scB + deltaB, scW + deltaW);
                else {
                    score = -pvs(nb, nw, 3 - turn, depth - 1, -alpha - 1, -alpha, nextHash, scB + deltaB, scW + deltaW);
                    if (score > alpha && score < beta) score = -pvs(nb, nw, 3 - turn, depth - 1, -beta, -alpha, nextHash, scB + deltaB, scW + deltaW);
                }
                if (score > bestScore) { bestScore = score; bestMove = m; }
                alpha = Math.max(alpha, score); if (alpha >= beta) break; 
             }
             if (!bestMove) bestMove = {r:7, c:7};
             return { val: bestScore, move: bestMove };
        }

        function pvs(b, w, turn, depth, alpha, beta, hash, scB, scW) {
            nodes++;
            let ttEntry = TT.get(hash);
            if (ttEntry && ttEntry.depth >= depth) {
                if (ttEntry.flag === 0) return ttEntry.score;
                if (ttEntry.flag === 1) alpha = Math.max(alpha, ttEntry.score);
                else if (ttEntry.flag === 2) beta = Math.min(beta, ttEntry.score);
                if (alpha >= beta) { cutoffs++; return ttEntry.score; }
            }
            if (depth === 0) return quiescence(b, w, turn, alpha, beta, 4, scB, scW);
            if (turn === 1 && scW > 500000000) return -INF + depth; 
            if (turn === 2 && scB > 500000000) return -INF + depth; 

            let cands = getRankedCands(b, w, turn, depth, ttEntry ? ttEntry.move : null, false);
            if (cands.length === 0) return (turn === 1) ? (scB - scW) : -(scB - scW);
            
            let val = -INF; let bestM = null; let originalAlpha = alpha;
            for (let i = 0; i < cands.length; i++) {
                let m = cands[i];
                let pos = BigInt(m.r * 15 + m.c);
                if (turn === 1 && isForbidden(b | (1n << pos), w, pos)) continue;
                let nb = turn === 1 ? b | (1n << pos) : b; let nw = turn === 2 ? w | (1n << pos) : w;
                let nextHash = hash ^ ZOBRIST[turn-1][m.r*15 + m.c];
                
                let nextDepth = depth - 1;
                if (depth >= 3 && i >= 4 && !checkWin(turn===1?nb:nw, pos)) { nextDepth--; }
                
                let score = -pvs(nb, nw, 3 - turn, nextDepth, -beta, -alpha, nextHash, scB, scW);
                if (nextDepth < depth - 1 && score > alpha) {
                    score = -pvs(nb, nw, 3 - turn, depth - 1, -beta, -alpha, nextHash, scB, scW);
                }
                if (score > val) { val = score; bestM = m; }
                alpha = Math.max(alpha, val);
                if (alpha >= beta) { cutoffs++; storeKiller(depth, m); HISTORY[turn-1][m.r*15 + m.c] += depth * depth; break; }
            }
            let flag = 0; if (val <= originalAlpha) flag = 2; else if (val >= beta) flag = 1; 
            storeTT(hash, depth, val, flag, bestM);
            return val;
        }
        function storeTT(hash, depth, score, flag, move) {
            let entry = TT.get(hash); if (entry && entry.depth > depth) return; 
            if (TT.size > MAX_TT_SIZE && !entry) { const oldest = TT.keys().next().value; TT.delete(oldest); }
            TT.set(hash, { depth, score, flag, move });
        }
        function quiescence(b, w, turn, alpha, beta, qsDepth, scB, scW) {
            nodes++;
            let totalScore = scB - scW; if (turn === 1) totalScore += 500; else totalScore -= 500;
            let standPat = (turn === 1) ? totalScore : -totalScore;
            if (standPat >= beta) return beta; if (standPat > alpha) alpha = standPat;
            if (qsDepth <= 0) return standPat;
            
            let cands = getRankedCands(b, w, turn, 30, null, false);
            let noisyMoves = []; 
            for(let m of cands) { if (m.s >= 10000000) noisyMoves.push(m); } 

            for (let m of noisyMoves) {
                let pos = BigInt(m.r * 15 + m.c);
                if (turn === 1 && isForbidden(b | (1n << pos), w, pos)) continue;
                let nb = turn === 1 ? b | (1n << pos) : b; let nw = turn === 2 ? w | (1n << pos) : w;
                let score = -quiescence(nb, nw, 3 - turn, -beta, -alpha, qsDepth - 1, scB, scW);
                if (score > alpha) { alpha = score; if (score >= beta) return beta; }
            }
            return alpha;
        }

        function evalFull(my, opp) {
             // simplified static eval
             return 0;
        }

        // --- VCT/VCF Fixed Logic ---
        function solveVCT(b, w, turn, depth, path) {
            if (depth > 6 || Date.now() - startTime > 3000) return null; 
            let cands = getRankedCands(b, w, turn, 0, null, false).slice(0, 15);
            let forcingMoves = [];
            for(let m of cands) if (m.s >= 20000000) forcingMoves.push(m);
            
            for (let atk of forcingMoves) {
                let pos = BigInt(atk.r * 15 + atk.c);
                if (turn === 1 && isForbidden(b | (1n << pos), w, pos)) continue;
                let nextB = (turn === 1 ? (b | (1n << pos)) : b); let nextW = (turn === 2 ? (w | (1n << pos)) : w);
                if (checkWin(turn===1?nextB:nextW, pos)) return [...path, atk];
                let type = getThreatType(turn===1?nextB:nextW, b|w|(1n<<pos), pos);
                if (type < 2) continue; 
                let defenses = getDefenses(nextB, nextW, 3-turn, type, pos, turn===1?nextB:nextW);
                if (defenses.length === 0) return [...path, atk];
                let solvedAll = true; let subPath = null;
                for (let def of defenses) {
                    let dPos = BigInt(def.r * 15 + def.c);
                    let newB = (turn === 2 ? (nextB | (1n << dPos)) : nextB); let newW = (turn === 1 ? (nextW | (1n << dPos)) : nextW);
                    if (checkWin(turn===2?newB:newW, dPos)) { solvedAll = false; break; } 
                    let res = solveVCT(newB, newW, turn, depth + 1, [...path, atk, def]);
                    if (!res) { solvedAll = false; break; }
                    subPath = res;
                }
                if (solvedAll) return subPath;
            }
            return null;
        }

        function solveVCF(b, w, turn, depth, path) {
             if (depth > 12 || Date.now() - startTime > 1500) return null;
             let attacks = getRankedCands(b, w, turn, 0, null, false).filter(m => m.s >= 50000000); 
             for (let atk of attacks) {
                 let pos = BigInt(atk.r * 15 + atk.c);
                 if (turn === 1 && isForbidden(b | (1n << pos), w, pos)) continue;
                 let nextB = (turn === 1 ? (b | (1n << pos)) : b); let nextW = (turn === 2 ? (w | (1n << pos)) : w);
                 if (checkWin(turn===1?nextB:nextW, pos)) return [...path, atk];
                 let defenses = getDefenses(nextB, nextW, 3-turn, 2, pos, turn===1?nextB:nextW);
                 if (defenses.length === 0) return [...path, atk]; 
                 let solvedAll = true; let subPath = null;
                 for (let def of defenses) {
                     let dPos = BigInt(def.r * 15 + def.c);
                     let newB = (turn === 2 ? (nextB | (1n << dPos)) : nextB); let newW = (turn === 1 ? (nextW | (1n << dPos)) : nextW);
                     if (checkWin(turn===2?newB:newW, dPos)) { solvedAll = false; break; }
                     let res = solveVCF(newB, newW, turn, depth + 1, [...path, atk, def]);
                     if (!res) { solvedAll = false; break; }
                     subPath = res;
                 }
                 if (solvedAll) return subPath;
             }
             return null;
        }

        // *** FIXED THREAT DETECTION ***
        function getThreatType(my, occ, pos) {
            let r = Number(pos / 15n), c = Number(pos % 15n);
            let fourFound = false; let threeFound = false;
            for (let dir of DIRECTIONS) {
                let count = 1; 
                let p = pos - dir; while (p >= 0n && (my & (1n << p)) && isValid(p, pos, dir)) { count++; p -= dir; }
                p = pos + dir; while (p < 225n && (my & (1n << p)) && isValid(p, pos, dir)) { count++; p += dir; }
                if (count >= 4) return 2; 
                
                let pattern = "";
                for(let k=-4; k<=4; k++) {
                    let p = pos + BigInt(k)*dir;
                    if (isValid(p, pos, dir, k)) {
                        if ((my >> p) & 1n) pattern += "1";
                        else if ((occ >> p) & 1n) pattern += "2";
                        else pattern += "0";
                    } else pattern += "2";
                }
                if (pattern.includes("11110") || pattern.includes("01111") || 
                    pattern.includes("10111") || pattern.includes("11101") || pattern.includes("11011")) fourFound = true;
                if (pattern.includes("01110") || pattern.includes("010110") || pattern.includes("011010")) threeFound = true;
            }
            if (fourFound) return 2;
            if (threeFound) return 1;
            return 0; 
        }
        function isValid(p, origin, dir, k) {
            if (p < 0n || p >= 225n) return false;
            let r1 = Number(origin/15n), c1 = Number(origin%15n);
            let r2 = Number(p/15n), c2 = Number(p%15n);
            if (dir === 1n && r1 !== r2) return false;
            return true;
        }

        function getDefenses(b, w, turn, threatType, atkPos, attackerBoard) { 
             let candidates = getRankedCands(b, w, turn, 0, null, false).slice(0, 12);
             let valid = [];
             for(let m of candidates) {
                 let dPos = BigInt(m.r * 15 + m.c);
                 if (turn === 1 && isForbidden(b | (1n << dPos), w, dPos)) continue;
                 let myNext = (turn === 1 ? b | (1n << dPos) : w | (1n << dPos));
                 let occ = b | w | (1n << dPos);
                 if (getThreatType(myNext, occ, dPos) >= threatType) { valid.push(m); continue; }
                 let newOcc = b | w | (1n << dPos);
                 let stillThreat = getThreatType(attackerBoard, newOcc, atkPos);
                 if (stillThreat < threatType) { valid.push(m); }
             }
             return valid.slice(0, 8);
        }

        function findWinMove(b, w, turn) {
            let occ = b | w;
            for(let i=0; i<225; i++) {
                if (occ & (1n << BigInt(i))) continue;
                let pos = BigInt(i); let r = Math.floor(i/15), c = i%15;
                if(!hasNeighbor(occ, r, c)) continue;
                if (turn === 1) { if (!isForbidden(b|(1n<<pos), w, pos) && checkWin(b|(1n<<pos), pos)) return {r,c}; } 
                else { if (checkWin(w|(1n<<pos), pos)) return {r,c}; }
            }
            return null;
        }
        function getRankedCands(b, w, p, depth, ttMove, addNoise) {
            let occ = b | w; let my = p === 2 ? w : b; let opp = p === 2 ? b : w;
            let list = []; let k1 = null, k2 = null;
            if (depth < 60) { k1 = KILLER[depth][0]; k2 = KILLER[depth][1]; }
            for(let i=0; i<225; i++) {
                if (occ & (1n << BigInt(i))) continue;
                let r = Math.floor(i/15), c = i%15;
                if (!hasNeighbor(occ, r, c)) continue;
                let score = evalMoveUltra(my, opp, b, w, r, c, p);
                score += POS_WEIGHTS[i];
                if (ttMove && ttMove.r === r && ttMove.c === c) score += 2000000000;
                else if (k1 && k1.r === r && k1.c === c) score += 1000000000;
                else if (k2 && k2.r === r && k2.c === c) score += 900000000;
                score += HISTORY[p-1][i]; score += MCTS_SCORES[i]; 
                if (addNoise) score += Math.floor(Math.random() * 50);
                list.push({r, c, s: score});
            }
            return list.sort((x,y) => y.s - x.s).slice(0, 30); 
        }
        function hasNeighbor(occ, r, c) {
             for(let dr=-2; dr<=2; dr++) for(let dc=-2; dc<=2; dc++) {
                 if (dr===0 && dc===0) continue;
                 let nr = r+dr, nc = c+dc;
                 if (nr>=0 && nr<15 && nc>=0 && nc<15) if (occ & (1n << BigInt(nr*15+nc))) return true;
             }
             return false;
        }
        
        function evalMoveUltra(my, opp, b, w, r, c, p) {
            let score = 0; const occ = b | w;
            const knightDirs = [[-2, -1], [-2, 1], [-1, -2], [-1, 2], [1, -2], [1, 2], [2, -1], [2, 1]];
            for(let [dr, dc] of knightDirs) {
                let nr = r+dr, nc = c+dc;
                if (nr>=0 && nr<15 && nc>=0 && nc<15 && (my & (1n << BigInt(nr*15+nc)))) score += 500; 
            }
            for (let dir of DIRECTIONS) {
                // --- BLOCKING OPPONENT LOGIC (Improved for Jumped 4s) ---
                let pattern = "";
                for(let k=-4; k<=4; k++) {
                    if (k===0) { pattern += "1"; continue; } // My stone is 1 (blocker)
                    let p = BigInt(r*15+c) + BigInt(k)*dir;
                    if (isValid(p, BigInt(r*15+c), dir, k)) {
                        if ((opp >> p) & 1n) pattern += "2";
                        else if ((my >> p) & 1n) pattern += "1";
                        else pattern += "0";
                    } else pattern += "1"; // Wall
                }
                // Check if opponent had a 4 or 3 that is now blocked
                // We simulate: if I wasn't there, would it be 5?
                // A simpler way: Check length of '2's ignoring my '1' (treating my 1 as 2)
                let ol=0, or=0;
                let lp = BigInt(r*15+c) - dir; while (lp>=0n && (opp & (1n<<lp)) && isValid(lp, BigInt(r*15+c), dir)) { ol++; lp-=dir; }
                let rp = BigInt(r*15+c) + dir; while (rp<225n && (opp & (1n<<rp)) && isValid(rp, BigInt(r*15+c), dir)) { or++; rp+=dir; }
                let straightLen = ol + 1 + or;
                
                if (straightLen >= 5) score += 950000000;
                else if (straightLen === 4) score += 150000000; 
                else if (straightLen === 3 && ol>0 && or>0) score += 20000000; // Jumped 3 block

                // Check Jumped 4 Block: "2 2 1 2 2" (Opponent was 2 2 _ 2 2)
                if (pattern.includes("22122") || pattern.includes("21222") || pattern.includes("22212")) score += 900000000;
            }
            return score;
        }

        function checkWin(my, pos) {
            let r = Number(pos / 15n), c = Number(pos % 15n);
            for (let dir of DIRECTIONS) {
                let count = 1;
                let p = pos - dir; while (p >= 0n && (my & (1n << p)) && isValid(p, pos, dir)) { count++; p -= dir; }
                p = pos + dir; while (p < 225n && (my & (1n << p)) && isValid(p, pos, dir)) { count++; p += dir; }
                if (count >= 5) return true;
            }
            return false;
        }

        function isForbidden(b, w, pos) {
            const occ = b | w; let threes = 0, fours = 0;
            let r = Number(pos / 15n), c = Number(pos % 15n);
            for (let dir of DIRECTIONS) {
                let left = 0, right = 0;
                let lp = pos - dir; while (lp >= 0n && (b & (1n << lp)) && isValid(lp, pos, dir)) { left++; lp -= dir; }
                let rp = pos + dir; while (rp < 225n && (b & (1n << rp)) && isValid(rp, pos, dir)) { right++; rp += dir; }
                let len = left + 1 + right;
                if (len > 5) return true; // Overline

                // Pattern Matching for 3x3, 4x4 (Better than simple length)
                // Extract 9 cells
                let pat = "";
                for(let k=-4; k<=4; k++) {
                     let p = pos + BigInt(k)*dir;
                     if (isValid(p, pos, dir, k)) {
                         if ((b >> p) & 1n) pat += "1"; else if ((w >> p) & 1n) pat += "2"; else pat += "0";
                     } else pat += "2";
                }
                // Check 4s: 1111, 10111, 11011, 11101
                if (pat.includes("1111") || pat.includes("10111") || pat.includes("11011") || pat.includes("11101")) fours++;
                
                // Check Open 3s: 01110, 010110, 011010
                if (pat.includes("01110") || pat.includes("010110") || pat.includes("011010")) threes++;
            }
            return (threes >= 2 || fours >= 2);
        }
        `;
        // ==========================================
        // [END WORKER CODE]
        // ==========================================

        const canvas = document.getElementById('vBoard');
        const ctx = canvas.getContext('2d');
        const status = document.getElementById('v_status');
        const forbiddenMsg = document.getElementById('v_forbidden');
        const nodeStat = document.getElementById('s_nodes');
        const modeStat = document.getElementById('s_mode');
        const scoreStat = document.getElementById('s_depth');
        const uRole = document.getElementById('u_role');
        const aRole = document.getElementById('a_role');
        const size = 15; const cell = 35; const margin = 45; 
        
        let board = Array.from({length: size}, () => Array(size).fill(0));
        let isGameOver = false; let moveHistory = []; let mousePos = null; let hintPos = null; let humanColor = 1; let forbiddenMap = [];

        const blob = new Blob([workerSource], {type: 'text/javascript'});
        const worker = new Worker(window.URL.createObjectURL(blob));

        worker.onmessage = function(e) {
            const d = e.data;
            if (d.type === 'HINT_RESULT') { if (d.move) { hintPos = d.move; drawBoard(); status.innerText = '💡 힌트 위치 표시됨'; } return; }
            if (d.type === 'RESULT') {
                if (d.nodes < 1000) nodeStat.innerText = d.nodes;
                else nodeStat.innerText = (d.nodes/1000).toFixed(1) + 'k';
                modeStat.innerText = d.note || 'THINK';
                scoreStat.innerText = d.depth;
                placeStone(d.move.r, d.move.c, 3 - humanColor); 
                let msg = d.note ? `⚡ ${d.note}` : `당신의 차례입니다`;
                status.innerText = msg;
            }
        };

        // ==========================================
        // [IMPROVED UI FORBIDDEN CHECK] 
        // Handles Jumped 4s (10111) and Jumped 3s correctly
        // ==========================================
        function checkForbidden(r, c) {
            // Temporarily place black stone
            let original = board[r][c];
            board[r][c] = 1;

            let threes = 0;
            let fours = 0;
            let overline = false;
            
            // Check all 4 directions
            const dirs = [[0,1],[1,0],[1,1],[1,-1]]; // H, V, D1, D2
            
            for (let [dr, dc] of dirs) {
                // Get pattern string for window of 9 cells
                // "1": Black, "2": White/Wall, "0": Empty
                let pat = "";
                for(let k=-4; k<=4; k++) {
                    let nr = r + k*dr;
                    let nc = c + k*dc;
                    if (nr >= 0 && nr < 15 && nc >= 0 && nc < 15) {
                        if (board[nr][nc] === 1) pat += "1";
                        else if (board[nr][nc] === 2) pat += "2";
                        else pat += "0";
                    } else {
                        pat += "2"; // Wall is opponent
                    }
                }

                // Check Overline (6 or more 1s consecutively)
                // We just count max consecutive 1s in the pattern
                let maxCon = 0; let curCon = 0;
                for (let char of pat) {
                    if (char === '1') curCon++;
                    else { maxCon = Math.max(maxCon, curCon); curCon = 0; }
                }
                maxCon = Math.max(maxCon, curCon);
                if (maxCon >= 6) overline = true;

                // Check Fours: 1111, 10111, 11011, 11101 (Jumped 4s included!)
                if (pat.includes("1111") || pat.includes("10111") || pat.includes("11011") || pat.includes("11101")) {
                    fours++;
                }

                // Check Open Threes: 01110, 010110, 011010
                if (pat.includes("01110") || pat.includes("010110") || pat.includes("011010")) {
                    threes++;
                }
            }
            
            // Revert
            board[r][c] = original;

            if (overline) return "6목 (장목)";
            if (fours >= 2) return "4-4 (쌍사)";
            if (threes >= 2) return "3-3 (쌍삼)";
            return null;
        }

        function updateForbiddenMap() { forbiddenMap = []; if (humanColor !== 1) return; for(let r=0; r<size; r++) for(let c=0; c<size; c++) if (board[r][c] === 0 && checkForbidden(r, c)) forbiddenMap.push({r,c}); }
        function checkWinLocal(p) {
             const dirs = [[0,1],[1,0],[1,1],[1,-1]];
             for (let i = 0; i < size; i++) for (let j = 0; j < size; j++) {
                 if (board[i][j] !== p) continue;
                 for (let [dx, dy] of dirs) {
                     let count = 1;
                     let x = i + dx, y = j + dy; while (x >= 0 && x < size && y >= 0 && y < size && board[x][y] === p) { count++; x += dx; y += dy; }
                     x = i - dx; y = j - dy; while (x >= 0 && x < size && y >= 0 && y < size && board[x][y] === p) { count++; x -= dx; y -= dy; }
                     if (count >= 5) return true;
                 }
             }
             return false;
        }

        function placeStone(r, c, p) {
            if (board[r][c] !== 0) return;
            if (p === 1 && moveHistory.length === 0) {
                if (r !== 7 || c !== 7) {
                    forbiddenMsg.innerText = '⚠️ 규칙: 첫 수는 중앙(천원) 필수입니다.';
                    shakeBoard();
                    return;
                }
            }
            if (p === 1) { let err = checkForbidden(r, c); if (err) { forbiddenMsg.innerText = `❌ 금수 위치: ${err}`; shakeBoard(); return; } }
            board[r][c] = p; moveHistory.push({r, c, p}); hintPos = null; updateForbiddenMap(); drawBoard();
            if (checkWinLocal(p)) {
                status.innerText = (p === humanColor ? '🏆 승리했습니다!' : '💀 AI가 승리했습니다.');
                status.style.color = p === humanColor ? '#28a745' : '#dc3545'; isGameOver = true; return;
            }
            if (p === humanColor) {
                status.innerText = '🛡️ AI 생각 중...'; status.style.color = '#555'; forbiddenMsg.innerText = '';
                let b = 0n, w = 0n;
                for(let rr=0; rr<size; rr++) for(let cc=0; cc<size; cc++) {
                    if(board[rr][cc]===1) b |= (1n << BigInt(rr*15 + cc));
                    if(board[rr][cc]===2) w |= (1n << BigInt(rr*15 + cc));
                }
                let hStr = moveHistory.map(m => `${m.r},${m.c}`).join("|");
                worker.postMessage({ type: 'THINK', b: b.toString(), w: w.toString(), turn: 3 - humanColor, history: hStr });
            }
        }
        window.requestHint = () => {
             if(isGameOver || status.innerText.includes('AI')) return;
             status.innerText = '🤖 족보 및 힌트 검색 중...';
             let b = 0n, w = 0n;
             for(let rr=0; rr<size; rr++) for(let cc=0; cc<size; cc++) {
                 if(board[rr][cc]===1) b |= (1n << BigInt(rr*15 + cc));
                 if(board[rr][cc]===2) w |= (1n << BigInt(rr*15 + cc));
             }
             let hStr = moveHistory.map(m => `${m.r},${m.c}`).join("|");
             worker.postMessage({ type: 'HINT', b: b.toString(), w: w.toString(), turn: humanColor, history: hStr });
        }
        function drawBoard() {
            ctx.fillStyle = '#DCB35C'; 
            ctx.fillRect(0, 0, canvas.width, canvas.height); 
            
            ctx.strokeStyle = '#000000'; ctx.lineWidth = 1; ctx.font = '12px sans-serif';
            ctx.fillStyle = '#000000';
            ctx.textAlign = 'center'; ctx.textBaseline = 'middle';
            const cols = "ABCDEFGHIJKLMNO";
            for (let i=0; i<size; i++) {
                let pos = margin + i * cell;
                ctx.fillText(cols[i], pos, margin - 20); ctx.fillText(cols[i], pos, margin + (size-1)*cell + 20);
                let num = 15 - i; ctx.fillText(num, margin - 25, pos); ctx.fillText(num, margin + (size-1)*cell + 25, pos);
                
                ctx.beginPath();
                ctx.moveTo(pos, margin); ctx.lineTo(pos, margin + (size-1)*cell);
                ctx.moveTo(margin, pos); ctx.lineTo(margin + (size-1)*cell, pos);
                ctx.stroke();
            }
            
            ctx.fillStyle = '#000000';
            [3, 7, 11].forEach(r => [3, 7, 11].forEach(c => { ctx.beginPath(); ctx.arc(margin + c*cell, margin + r*cell, 3.5, 0, Math.PI*2); ctx.fill(); }));

            if (humanColor === 1 && !isGameOver) {
                ctx.strokeStyle = 'rgba(231, 76, 60, 0.7)'; ctx.lineWidth = 2;
                for (let f of forbiddenMap) {
                    let fx = margin + f.c * cell; let fy = margin + f.r * cell;
                    ctx.beginPath(); ctx.moveTo(fx - 4, fy - 4); ctx.lineTo(fx + 4, fy + 4);
                    ctx.moveTo(fx + 4, fy - 4); ctx.lineTo(fx - 4, fy + 4); ctx.stroke();
                }
            }
            
            let moveMap = new Map();
            moveHistory.forEach((m, idx) => { moveMap.set(m.r + "," + m.c, idx + 1); });

            for(let r=0; r<size; r++) {
                for(let c=0; c<size; c++) {
                    if (board[r][c] !== 0) {
                        let num = moveMap.get(r + "," + c);
                        drawStone(r, c, board[r][c], num);
                    }
                }
            }

            if (hintPos && !isGameOver) {
                let cx = margin + hintPos.c * cell; let cy = margin + hintPos.r * cell;
                ctx.strokeStyle = '#27ae60'; ctx.lineWidth = 3; ctx.setLineDash([5,5]);
                ctx.beginPath(); ctx.arc(cx, cy, 18, 0, Math.PI*2); ctx.stroke(); ctx.setLineDash([]);
            }
            
            if (mousePos && board[mousePos.r][mousePos.c] === 0 && !isGameOver && !status.innerText.includes('AI')) {
                ctx.globalAlpha = 0.6; drawStone(mousePos.r, mousePos.c, humanColor, null); ctx.globalAlpha = 1.0;
                if (humanColor === 1) {
                    let err = checkForbidden(mousePos.r, mousePos.c);
                    if (err) {
                        forbiddenMsg.innerText = `⚠️ 금수: ${err}`;
                        let cx = margin + mousePos.c * cell; let cy = margin + mousePos.r * cell;
                        ctx.strokeStyle = '#c0392b'; ctx.lineWidth = 3;
                        ctx.beginPath(); ctx.moveTo(cx - 8, cy - 8); ctx.lineTo(cx + 8, cy + 8);
                        ctx.moveTo(cx + 8, cy - 8); ctx.lineTo(cx - 8, cy + 8); ctx.stroke();
                    } else forbiddenMsg.innerText = '';
                }
            }
            
            if (moveHistory.length > 0) {
                let last = moveHistory[moveHistory.length-1];
                let lx = margin + last.c * cell; let ly = margin + last.r * cell;
                ctx.strokeStyle = '#e74c3c'; ctx.lineWidth = 2; ctx.beginPath(); ctx.arc(lx, ly, 17, 0, Math.PI*2); ctx.stroke();
            }
        }
        function drawStone(r, c, type, num) {
            let cx = margin + c * cell; let cy = margin + r * cell;
            ctx.fillStyle = 'rgba(0,0,0,0.4)';
            ctx.beginPath(); ctx.arc(cx + 2, cy + 2, 16, 0, Math.PI*2); ctx.fill();

            let grad = ctx.createRadialGradient(cx - 5, cy - 5, 2, cx, cy, 15);
            if (type === 1) { grad.addColorStop(0, '#555'); grad.addColorStop(1, '#000'); } 
            else { grad.addColorStop(0, '#fff'); grad.addColorStop(1, '#ddd'); } 
            ctx.fillStyle = grad;
            ctx.beginPath(); ctx.arc(cx, cy, 16, 0, Math.PI*2); ctx.fill();

            if (num !== null) {
                ctx.fillStyle = (type === 1) ? '#fff' : '#000';
                ctx.font = 'bold 12px sans-serif';
                ctx.textAlign = 'center'; ctx.textBaseline = 'middle';
                ctx.fillText(num, cx, cy);
            }
        }
        window.resetVoid = () => {
            board = Array.from({length: size}, () => Array(size).fill(0));
            isGameOver = false; moveHistory = []; hintPos = null; forbiddenMap = []; humanColor = 1; 
            updateRoleDisplay(); status.innerText = '🔥 게임 준비 완료'; forbiddenMsg.innerText = '';
            worker.postMessage({type: 'RESET'}); drawBoard();
        };
        window.swapSides = () => {
            if (moveHistory.length > 0) { alert("게임 도중에는 바꿀 수 없습니다. 새 게임을 시작한 후 바꾸세요."); return; }
            humanColor = 3 - humanColor; updateRoleDisplay(); updateForbiddenMap(); drawBoard();
            if (humanColor === 2) { status.innerText = '🛡️ AI가 먼저 시작합니다...'; worker.postMessage({ type: 'THINK', b: '0', w: '0', turn: 1, history: "" }); } 
            else status.innerText = '👤 흑돌(선수)을 잡았습니다';
        };
        function updateRoleDisplay() {
            if (humanColor === 1) { uRole.innerText = "흑 (선수)"; uRole.style.color = "#000"; aRole.innerText = "백 (후수)"; aRole.style.color = "#888"; } 
            else { uRole.innerText = "백 (후수)"; uRole.style.color = "#000"; aRole.innerText = "흑 (선수)"; aRole.style.color = "#888"; }
        }
        window.undoMove = () => {
            if (moveHistory.length < 2 || isGameOver) return;
            for(let k=0; k<2; k++) { let m = moveHistory.pop(); if(m) board[m.r][m.c] = 0; }
            isGameOver = false; hintPos = null; updateForbiddenMap(); status.innerText = '↶ 무르기 완료'; drawBoard();
        };
        function shakeBoard() { canvas.style.transform = "translateX(5px)"; setTimeout(() => canvas.style.transform = "translateX(-5px)", 50); setTimeout(() => canvas.style.transform = "translateX(0)", 100); }
        function getMousePos(e) {
            const rect = canvas.getBoundingClientRect(); const scaleX = canvas.width / rect.width; const scaleY = canvas.height / rect.height;
            let x = (e.clientX - rect.left) * scaleX; let y = (e.clientY - rect.top) * scaleY;
            return { c: Math.round((x - margin) / cell), r: Math.round((y - margin) / cell) };
        }
        canvas.onmousemove = (e) => {
            if (isGameOver) return; let pos = getMousePos(e);
            if (pos.r >= 0 && pos.r < size && pos.c >= 0 && pos.c < size) { if (!mousePos || mousePos.r !== pos.r || mousePos.c !== pos.c) { mousePos = pos; drawBoard(); } } 
            else { if (mousePos) { mousePos = null; drawBoard(); } }
        };
        canvas.onmouseleave = () => { mousePos = null; drawBoard(); };
        canvas.onclick = (e) => {
            if (isGameOver || status.innerText.includes('AI')) return; let pos = getMousePos(e);
            if (pos.r >= 0 && pos.r < size && pos.c >= 0 && pos.c < size) if (board[pos.r][pos.c] === 0) placeStone(pos.r, pos.c, humanColor);
        };
        drawBoard(); updateRoleDisplay(); status.innerText = '클릭하여 시작하세요';
    })();
    </script>
</body>
</html>
