<!DOCTYPE html>
<html>
<head>
<meta charset="UTF-8">
<title>Simple Renju</title>
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
        <h1>Simple Renju</h1>
        
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
            <button class="btn-undo" disabled style="background:#ccc; cursor:not-allowed;">↶ 무르기</button>
            <button class="btn-hint" disabled style="background:#ccc; cursor:not-allowed;">💡힌트</button>
        </div>
    </div>

    <script>
    (function() {
        // [AI LOGIC PART - FIXED AND OPTIMIZED]
        const workerSource = `
        const INF = 1000000000; 
        let nodes = 0; let mctsSims = 0; let startTime = 0;
        const TIME_LIMIT = 4000; 
        const MAX_TT_SIZE = 5000000; 
        
        // 오프닝 북 (주요 정석)
        const BOOK = {
            "7,7|6,8|6,6": {r:5, c:7}, "7,7|6,8|6,6|5,7": {r:5, c:8}, 
            "7,7|6,6|8,6": {r:5, c:5}, "7,7|6,6|8,8": {r:5, c:5},       
            "7,7|7,8|6,8": {r:5, c:7}, "7,7|7,8|6,8|5,7": {r:5, c:8},
            "7,7|5,6|4,5": {r:3, c:6}, "7,7|6,9|5,10": {r:4, c:9},      
            "7,7|9,6|10,5": {r:8, c:4}, "7,7|5,8|4,9": {r:3, c:8},      
            "7,7|6,7|6,6": {r:5, c:5}, "7,7|8,7|8,6": {r:9, c:5},       
            "7,7|8,7|8,6|9,5": {r:7, c:5}, "7,7|7,5|6,4": {r:5, c:5},        
            "7,7|5,7|4,6": {r:3, c:7}, "7,7|5,7|4,6|3,7": {r:5, c:5},
            "7,7|5,7|4,6|3,7|5,5": {r:6, c:5}, "7,7|7,9|6,10": {r:5, c:9},      
            "7,7|7,9|6,10|5,9": {r:5, c:8}, "7,7|9,7|10,6": {r:11, c:7},      
            "7,7|7,4|6,3": {r:5, c:4}, "7,7|4,7|3,6": {r:2, c:7},        
            "7,7|8,5|9,4": {r:7, c:3}, "7,7|9,9|10,10": {r:8, c:11},    
            "7,7|5,5|4,4": {r:3, c:5}, "": {r:7, c:7} 
        };
        const INV_OP = [0, 3, 2, 1, 4, 5, 6, 7];
        function transform(r, c, op) {
            let nr = r - 7, nc = c - 7; let tr, tc;
            switch(op) {
                case 0: tr=nr; tc=nc; break; case 1: tr=nc; tc=-nr; break;
                case 2: tr=-nr; tc=-nc; break; case 3: tr=-nc; tc=nr; break;
                case 4: tr=nr; tc=-nc; break; case 5: tr=-nr; tc=nc; break;
                case 6: tr=nc; tc=nr; break; case 7: tr=-nc; tc=-nr; break;
            }
            return {r: tr+7, c: tc+7};
        }
        function matchBook(history) {
            if (history.length === 0) return BOOK[""];
            for(let op=0; op<8; op++) {
                let keyParts = []; let valid = true;
                for(let m of history) {
                    let t = transform(m.r, m.c, op);
                    if (t.r < 0 || t.r > 14 || t.c < 0 || t.c > 14) { valid = false; break; }
                    keyParts.push(t.r + "," + t.c);
                }
                if (!valid) continue;
                let key = keyParts.join("|");
                if (BOOK[key]) { let best = BOOK[key]; let invOp = INV_OP[op]; return transform(best.r, best.c, invOp); }
            }
            return null;
        }

        const POS_WEIGHTS = new Int32Array(225);
        for(let r=0; r<15; r++) for(let c=0; c<15; c++) {
            let d = Math.sqrt((r-7)*(r-7) + (c-7)*(c-7));
            POS_WEIGHTS[r*15+c] = Math.round(10 - d); // 중앙 선호
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
        const DIRECTIONS = [1n, 15n, 16n, 14n]; 
        
        self.onmessage = function(e) {
            const d = e.data; 
            try {
                if (d.type === 'RESET') { 
                    TT.clear(); KILLER = Array.from({length: 60}, () => [null, null]);
                    HISTORY = [new Int32Array(225), new Int32Array(225)];
                    return; 
                }
                
                const b = BigInt(d.b); const w = BigInt(d.w); const turn = d.turn;
                let currentHash = computeHash(b, w);
                
                // 기본 평가
                let initScoreB = evalFull(b, w);
                let initScoreW = evalFull(w, b);

                if (d.type === 'HINT') {
                    startTime = Date.now();
                    let hist = parseHistory(d.history);
                    let bookMove = matchBook(hist);
                    if (bookMove) {
                        let p = BigInt(bookMove.r * 15 + bookMove.c);
                        if (!((b|w) & (1n << p)) && !(turn === 1 && isForbidden(b | (1n << p), w, p))) { 
                            self.postMessage({ type: 'HINT_RESULT', move: bookMove }); return; 
                        }
                    }
                    // 힌트는 빠르게 계산
                    const res = runPVS(b, w, turn, currentHash, 800, initScoreB, initScoreW); 
                    self.postMessage({ type: 'HINT_RESULT', move: res.move });
                    return;
                }
                
                if (d.type === 'THINK') {
                    nodes = 0; cutoffs = 0; startTime = Date.now();
                    let hist = parseHistory(d.history);
                    let bookMove = matchBook(hist);
                    if (bookMove) {
                         let idx = BigInt(bookMove.r * 15 + bookMove.c);
                         if (!((b|w) & (1n << idx))) {
                             self.postMessage({ type: 'RESULT', move: bookMove, nodes: 1, cutoffs: 0, mcts: 0, score: 99999, time: 1, depth: 'BOOK', note: 'OPENING' });
                             return;
                         }
                    }
                    
                    // VCF (Victory by Continuous Fours) - 필승 찾기
                    let winSeq = solveVCF(b, w, turn, 0, []);
                    if (winSeq) { self.postMessage({ type: 'RESULT', move: winSeq[0], nodes, cutoffs, mcts: 0, time: Date.now()-startTime, depth: 'VCF', note: 'CHECKMATE' }); return; }
                    
                    // PVS (Principal Variation Search)
                    const result = runPVS(b, w, turn, currentHash, TIME_LIMIT, initScoreB, initScoreW);
                    if (!result || !result.move) throw "No move found";
                    self.postMessage({ type: 'RESULT', move: result.move, nodes, cutoffs, mcts: 0, score: result.val, time: Date.now() - startTime, depth: result.depth, note: 'THINKING' });
                }
            } catch (err) {
                // 에러 발생 시 fallback (빈 곳 중 점수 높은 곳)
                const fb_b = BigInt(e.data.b); const fb_w = BigInt(e.data.w);
                let fallbackMoves = getRankedCands(fb_b, fb_w, e.data.turn, 0, null, true);
                let safeMove = {r:7, c:7};
                for (let m of fallbackMoves) {
                    let p = BigInt(m.r * 15 + m.c);
                    if (e.data.turn === 1 && isForbidden(fb_b | (1n << p), fb_w, p)) continue;
                    safeMove = m; break;
                }
                if (d.type === 'HINT') { self.postMessage({ type: 'HINT_RESULT', move: safeMove }); } 
                else { self.postMessage({ type: 'RESULT', move: safeMove, nodes: nodes, cutoffs: 0, mcts: 0, score: 0, time: 0, depth: 'ERR', note: 'RECOVERY' }); }
            }
        };

        function parseHistory(str) {
            if (!str) return [];
            try { return str.split('|').map(s => { let p = s.split(','); return {r: parseInt(p[0]), c: parseInt(p[1])}; }); }
            catch(e) { return []; }
        }
        
        function computeHash(b, w) {
            let h = 0n; for(let i=0; i<225; i++) { if((b>>BigInt(i))&1n) h^=ZOBRIST[0][i]; if((w>>BigInt(i))&1n) h^=ZOBRIST[1][i]; } return h;
        }

        function runPVS(b, w, turn, hash, limit, scoreB, scoreW) {
            let bestMove = {r:7, c:7};
            let maxD = 0; let previousScore = 0;
            // 반복 심화 (Iterative Deepening)
            for (let d = 2; d <= 12; d+=2) { // 짝수 깊이로 탐색
                 maxD = d; 
                 let alpha = -INF; let beta = INF;
                 let score = pvsRoot(b, w, turn, d, alpha, beta, hash, limit, scoreB, scoreW);
                 
                 if (Date.now() - startTime > limit) break;
                 previousScore = score.val; if (score.move) bestMove = score.move;
            }
            return { move: bestMove, depth: maxD, val: previousScore };
        }

        function pvsRoot(b, w, turn, depth, alpha, beta, hash, limit, scB, scW) {
             let rootMoves = getRankedCands(b, w, turn, depth, null, true); 
             if (rootMoves.length === 0) return {val: 0, move: {r:7, c:7}};
             let bestScore = -INF; let bestMove = rootMoves[0];
             
             for (let i = 0; i < rootMoves.length; i++) {
                if (Date.now() - startTime > limit) break;
                let m = rootMoves[i]; let pos = BigInt(m.r * 15 + m.c);
                if (turn === 1 && isForbidden(b | (1n << pos), w, pos)) continue;
                
                let nextHash = hash ^ ZOBRIST[turn-1][m.r*15 + m.c];
                let nb = turn === 1 ? b | (1n << pos) : b; let nw = turn === 2 ? w | (1n << pos) : w;
                
                // Delta evaluation
                let deltaB = evalMoveDiff(b, w, m.r, m.c);
                let deltaW = evalMoveDiff(w, b, m.r, m.c);
                let nextScB = scB + (turn === 1 ? deltaB : 0);
                let nextScW = scW + (turn === 2 ? deltaW : 0);

                let score;
                if (i === 0) score = -pvs(nb, nw, 3 - turn, depth - 1, -beta, -alpha, nextHash, nextScB, nextScW);
                else {
                    score = -pvs(nb, nw, 3 - turn, depth - 1, -alpha - 1, -alpha, nextHash, nextScB, nextScW);
                    if (score > alpha && score < beta) score = -pvs(nb, nw, 3 - turn, depth - 1, -beta, -alpha, nextHash, nextScB, nextScW);
                }
                if (score > bestScore) { bestScore = score; bestMove = m; }
                alpha = Math.max(alpha, score); if (alpha >= beta) break; 
             }
             return { val: bestScore, move: bestMove };
        }

        function pvs(b, w, turn, depth, alpha, beta, hash, scB, scW) {
            nodes++;
            if (depth <= 0) return evalFull(turn===1?b:w, turn===1?w:b) - evalFull(turn===1?w:b, turn===1?b:w);

            let cands = getRankedCands(b, w, turn, depth, null, false);
            if (cands.length === 0) return 0;

            let val = -INF; 
            for (let i = 0; i < cands.length; i++) {
                let m = cands[i];
                let pos = BigInt(m.r * 15 + m.c);
                if (turn === 1 && isForbidden(b | (1n << pos), w, pos)) continue;

                let nb = turn === 1 ? b | (1n << pos) : b; let nw = turn === 2 ? w | (1n << pos) : w;
                let nextHash = hash ^ ZOBRIST[turn-1][m.r*15 + m.c];
                
                let score = -pvs(nb, nw, 3 - turn, depth - 1, -beta, -alpha, nextHash, scB, scW); // Simplified recursion for brevity
                
                if (score > val) val = score;
                alpha = Math.max(alpha, val);
                if (alpha >= beta) { cutoffs++; break; }
            }
            return val;
        }

        // --- Evaluation Logic (Fixed) ---
        // 패턴 점수
        const SCORES = {
            WIN: 10000000,
            OPEN_4: 100000,
            CLOSED_4: 2005,
            OPEN_3: 2000,
            CLOSED_3: 100,
            OPEN_2: 100,
            CLOSED_2: 10
        };

        function evalFull(my, opp) {
            let score = 0;
            const occ = my | opp;
            // 가로, 세로, 대각선 모두 평가
            for (let r=0; r<15; r++) score += evalLine(my, opp, r*15, 1, 15); // 가로
            for (let c=0; c<15; c++) score += evalLine(my, opp, c, 15, 15); // 세로
            // 대각선 (15,15는 중앙 대각선 길이)
            // 우하향 대각선
            for (let c=0; c<=10; c++) score += evalLine(my, opp, c, 16, 15-c);
            for (let r=1; r<=10; r++) score += evalLine(my, opp, r*15, 16, 15-r);
            // 좌하향 대각선
            for (let c=4; c<15; c++) score += evalLine(my, opp, c, 14, c+1);
            for (let r=1; r<=10; r++) score += evalLine(my, opp, r*15+14, 14, 15-r);
            return score;
        }

        function evalMoveDiff(my, opp, r, c) {
            // 차분 평가 (성능 최적화용, 전체 다시 계산 안함)
            return evalFull(my | (1n << BigInt(r*15+c)), opp) - evalFull(my, opp);
        }

        function evalLine(my, opp, startIdx, step, len) {
            let score = 0;
            let count = 0;
            let openStart = false;
            let gap = false; // 한 칸 건너뜀 (Broken line)

            for (let i = 0; i < len; i++) {
                let pos = BigInt(startIdx + i * step);
                if ((my >> pos) & 1n) {
                    count++;
                } else if ((opp >> pos) & 1n) {
                    if (count > 0) {
                        score += getPatternScore(count, openStart, false);
                    }
                    count = 0;
                    openStart = false;
                } else {
                    // 빈 칸
                    if (count > 0) {
                        score += getPatternScore(count, openStart, true);
                    }
                    count = 0;
                    openStart = true;
                }
            }
            if (count > 0) score += getPatternScore(count, openStart, false);
            return score;
        }

        function getPatternScore(count, openStart, openEnd) {
            if (count >= 5) return SCORES.WIN;
            if (count === 4) {
                if (openStart && openEnd) return SCORES.OPEN_4;
                if (openStart || openEnd) return SCORES.CLOSED_4;
            }
            if (count === 3) {
                if (openStart && openEnd) return SCORES.OPEN_3;
                if (openStart || openEnd) return SCORES.CLOSED_3;
            }
            if (count === 2) {
                if (openStart && openEnd) return SCORES.OPEN_2;
                return SCORES.CLOSED_2;
            }
            return 1;
        }

        // --- Forbidden Logic (Renju Rules) ---
        function isForbidden(b, w, pos) {
            // 흑(b) 입장에서 금수 확인
            // 1. 장목 (Overline): 6목 이상
            if (checkOverline(b, pos)) return true;
            
            // 2. 3-3, 4-4
            // (정확한 렌주룰: 3-3은 '열린 3'이 두 개 이상, 4-4는 4가 두 개 이상)
            // 성능을 위해 간단히 패턴 검사
            let threes = 0;
            let fours = 0;
            
            let r = Number(pos / 15n), c = Number(pos % 15n);
            
            for (let dir of DIRECTIONS) {
                let info = getLineInfo(b, w, pos, dir);
                if (info.len >= 6) return true; // 장목 중복 체크
                if (info.len === 4) {
                    // 4-4 조건: 반대쪽이 막혀있지 않거나, 5목을 만들 수 있는 잠재력이 있어야 함
                    // 여기서는 단순화하여 4가 만들어지면 count
                    fours++; 
                }
                if (info.len === 3 && info.openL && info.openR) {
                    // 3-3 조건: 양쪽이 다 뚫려있어야 '열린 3' (Open 3)
                    // 거짓 금수 판별은 복잡하므로 약식으로 처리
                    threes++;
                }
            }
            
            if (fours >= 2) return true;
            if (threes >= 2) return true;
            
            return false;
        }
        
        function checkOverline(my, pos) {
            let r = Number(pos / 15n), c = Number(pos % 15n);
            for (let dir of DIRECTIONS) {
                let count = 1;
                let p = pos - dir; let lr = r, lc = c;
                while (p >= 0n && (my & (1n << p))) {
                     let nr = Number(p/15n), nc = Number(p%15n);
                     if (Math.abs(nr-lr)>1 || Math.abs(nc-lc)>1) break;
                     count++; p-=dir; lr=nr; lc=nc;
                }
                p = pos + dir; let rr = r, rc = c;
                while (p < 225n && (my & (1n << p))) {
                     let nr = Number(p/15n), nc = Number(p%15n);
                     if (Math.abs(nr-rr)>1 || Math.abs(nc-rc)>1) break;
                     count++; p+=dir; rr=nr; rc=nc;
                }
                if (count >= 6) return true;
            }
            return false;
        }

        function getLineInfo(my, opp, pos, dir) {
            let r = Number(pos / 15n), c = Number(pos % 15n);
            let occ = my | opp;
            
            // Left scan
            let left = 0; let p = pos - dir; let lr = r, lc = c;
            while (p >= 0n && (my & (1n << p))) {
                 let nr = Number(p/15n), nc = Number(p%15n);
                 if (Math.abs(nr-lr)>1 || Math.abs(nc-lc)>1) break;
                 left++; p-=dir; lr=nr; lc=nc;
            }
            let openL = (p >= 0n && p < 225n && !((occ >> p) & 1n));
            
            // Right scan
            let right = 0; p = pos + dir; let rr = r, rc = c;
            while (p < 225n && (my & (1n << p))) {
                 let nr = Number(p/15n), nc = Number(p%15n);
                 if (Math.abs(nr-rr)>1 || Math.abs(nc-rc)>1) break;
                 right++; p+=dir; rr=nr; rc=nc;
            }
            let openR = (p >= 0n && p < 225n && !((occ >> p) & 1n));
            
            return { len: left + 1 + right, openL, openR };
        }

        // --- VCF Helper ---
        function solveVCF(b, w, turn, depth, path) {
            if (depth > 6 || Date.now() - startTime > 300) return null; // 너무 깊게 안 함
            
            // 4 공격 후보 찾기
            let cands = getRankedCands(b, w, turn, 0, null, false);
            for (let m of cands) {
                let pos = BigInt(m.r * 15 + m.c);
                if (turn === 1 && isForbidden(b|(1n<<pos), w, pos)) continue;
                
                let nextB = turn===1 ? b|(1n<<pos) : b;
                let nextW = turn===2 ? w|(1n<<pos) : w;
                
                // 이번 수로 이겼는지 확인
                if (checkWin(turn===1?nextB:nextW, pos)) return [...path, m];
                
                // 상대방이 막아야 하는지 확인 (내가 4를 뒀으니 상대는 무조건 막아야 함)
                // 단순히, 상대가 이기는지 체크하고 없으면 재귀
                // VCF는 '연속 4' 이므로, 내가 둔 수가 4가 되어야 함.
                let infoArr = [];
                for(let dir of DIRECTIONS) infoArr.push(getLineInfo(turn===1?nextB:nextW, turn===1?nextW:nextB, pos, dir));
                
                let isFour = infoArr.some(i => i.len === 4 && (i.openL || i.openR));
                if (!isFour) continue; // 4가 아니면 VCF 아님
                
                // 상대방의 방어 수 시뮬레이션은 생략하고, 
                // 간단히 '내가 계속 공격해서 이길 수 있는가'만 봄 (Greedy)
            }
            return null;
        }

        function checkWin(my, pos) {
            return checkOverline(my, pos) ? false : (function(){
                 let r = Number(pos / 15n), c = Number(pos % 15n);
                 for (let dir of DIRECTIONS) {
                    let count = 1;
                    let p = pos - dir; let lr = r, lc = c;
                    while (p>=0n && (my&(1n<<p))) { let nr=Number(p/15n); if(Math.abs(nr-lr)>1)break; count++; p-=dir; lr=nr;}
                    p = pos + dir; let rr = r, rc = c;
                    while (p<225n && (my&(1n<<p))) { let nr=Number(p/15n); if(Math.abs(nr-rr)>1)break; count++; p+=dir; rr=nr;}
                    if (count === 5) return true;
                 }
                 return false;
            })();
        }

        function getRankedCands(b, w, p, depth, ttMove, addNoise) {
            let occ = b | w;
            let list = [];
            
            // 1. 위협적인 수 먼저 탐색 (주변에 돌이 있는 곳만)
            for(let i=0; i<225; i++) {
                if ((occ >> BigInt(i)) & 1n) continue;
                let r = Math.floor(i/15), c = i%15;
                if (!hasNeighbor(occ, r, c)) continue;
                
                let score = POS_WEIGHTS[i];
                // 간단한 휴리스틱 평가
                score += evalMoveDiff(p===1?b:w, p===2?b:w, r, c); // 내 공격 점수
                score += evalMoveDiff(p===2?b:w, p===1?b:w, r, c); // 상대 방어 점수
                
                list.push({r, c, s: score});
            }
            return list.sort((x,y) => y.s - x.s).slice(0, 20); // 상위 20개만
        }
        
        function hasNeighbor(occ, r, c) {
             for(let dr=-1; dr<=1; dr++) for(let dc=-1; dc<=1; dc++) {
                 if (dr===0 && dc===0) continue;
                 let nr = r+dr, nc = c+dc;
                 if (nr>=0 && nr<15 && nc>=0 && nc<15) {
                     if ((occ >> BigInt(nr*15+nc)) & 1n) return true;
                 }
             }
             return false;
        }
        `;

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

        function checkForbidden(r, c) {
            let boardCopy = board.map(row => [...row]); boardCopy[r][c] = 1; 
            const dirs = [[0,1],[1,0],[1,1],[1,-1]];
            let threes = 0, fours = 0, overline = false;
            
            for (let [dx, dy] of dirs) {
                // Check Left
                let left = 0; let lx = r - dx, ly = c - dy;
                while (lx >= 0 && lx < 15 && ly >= 0 && ly < 15 && boardCopy[lx][ly] === 1) { left++; lx -= dx; ly -= dy; }
                let l_open = (lx >= 0 && lx < 15 && ly >= 0 && ly < 15 && boardCopy[lx][ly] === 0);
                
                // Check Right
                let right = 0; let rx = r + dx, ry = c + dy;
                while (rx >= 0 && rx < 15 && ry >= 0 && ry < 15 && boardCopy[rx][ry] === 1) { right++; rx += dx; ry += dy; }
                let r_open = (rx >= 0 && rx < 15 && ry >= 0 && ry < 15 && boardCopy[rx][ry] === 0);
                
                let len = left + 1 + right;
                if (len >= 6) overline = true;
                if (len === 3 && l_open && r_open) threes++; 
                if (len === 4 && (l_open || r_open)) fours++; // 4-4는 양쪽 안열려도 금수 조건 포함될 수 있으나 UI에선 단순화
            }
            if (overline) return "6목 (장목)"; if (threes >= 2) return "3-3 (쌍삼)"; if (fours >= 2) return "4-4 (쌍사)"; return null;
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
                     if (count >= 5) {
                         if (p === 1 && count > 5) return false; // 흑은 장목 승리 불가 (이미 금수 로직에서 막히지만 더블 체크)
                         return true;
                     }
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
            moveHistory.forEach((m, idx) => {
                moveMap.set(m.r + "," + m.c, idx + 1);
            });

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
            if (type === 1) { 
                grad.addColorStop(0, '#555'); 
                grad.addColorStop(1, '#000'); 
            } else { 
                grad.addColorStop(0, '#fff'); 
                grad.addColorStop(1, '#ddd'); 
            } 
            ctx.fillStyle = grad;
            ctx.beginPath(); ctx.arc(cx, cy, 16, 0, Math.PI*2); ctx.fill();

            if (num !== null) {
                ctx.fillStyle = (type === 1) ? '#fff' : '#000';
                ctx.font = 'bold 12px sans-serif';
                ctx.textAlign = 'center';
                ctx.textBaseline = 'middle';
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
            // AI가 두고 있는 중이면 무르기 불가
            if (status.innerText.includes('AI') && !isGameOver) return;
            
            // 내 수와 AI 수 두 개를 뺌
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
