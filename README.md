<!DOCTYPE html>
<html lang="ko">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>AI Baseball - 5</title>
    <style>
        * { box-sizing: border-box; }
        body { font-family: 'Segoe UI', sans-serif; background-color: #f8f9fa; color: #333; padding: 10px; margin: 0; display: flex; flex-direction: column; height: 100vh; }
        #header { text-align: center; flex-shrink: 0; }
        h2 { margin: 10px 0; color: #1a73e8; font-size: 1.2rem; }
        #status-bar { background: #fff; padding: 12px; border-radius: 12px; border: 1px solid #dee2e6; margin-bottom: 10px; box-shadow: 0 4px 6px rgba(0,0,0,0.05); display: flex; flex-direction: column; align-items: center; gap: 8px; flex-shrink: 0; }
        .vs-wrapper { display: flex; align-items: center; justify-content: center; gap: 15px; width: 100%; }
        .vs-item { display: flex; flex-direction: column; align-items: center; flex: 1; }
        .vs-label { font-size: 0.7em; color: #888; font-weight: bold; }
        .vs-prob { font-size: 1.2em; font-weight: 800; }
        .vs-text { font-size: 1em; font-weight: 900; color: #ccc; }
        .prob-player { color: #1a73e8; }
        .prob-com { color: #d93025; }
        .pool-stats { display: flex; width: 100%; justify-content: space-around; border-top: 1px solid #eee; padding-top: 8px; font-size: 0.75em; color: #666; }
        #terminal { border: 1px solid #dee2e6; padding: 12px; flex-grow: 1; overflow-y: auto; background-color: #ffffff; margin-bottom: 10px; font-size: 13px; border-radius: 12px; }
        .log-entry { margin-bottom: 6px; padding: 8px; border-radius: 8px; line-height: 1.4; }
        .system { background-color: #f1f3f4; color: #5f6368; border-left: 4px solid #dadce0; }
        .player { background-color: #e8f0fe; color: #1967d2; border-left: 4px solid #1a73e8; }
        .computer { background-color: #fce8e6; color: #c5221f; border-left: 4px solid #d93025; }
        .input-area { display: flex; gap: 8px; flex-shrink: 0; margin-bottom: 5px; }
        input { background: #fff; border: 2px solid #dee2e6; color: #333; padding: 12px; flex-grow: 1; outline: none; font-size: 16px; border-radius: 8px; }
        button { border: none; padding: 0 15px; cursor: pointer; font-weight: bold; font-size: 14px; border-radius: 8px; transition: 0.2s; }
        #sendBtn { background: #1a73e8; color: #fff; flex-grow: 1; height: 45px; }
        #restartBtn { background: #f1f3f4; color: #3c4043; height: 45px; }
    </style>
</head>
<body>
    <div id="header"><h2>5-Digit AI Baseball (Entropy)</h2></div>
    <div id="status-bar">
        <div class="vs-wrapper">
            <div class="vs-item"><span class="vs-label">PLAYER WIN %</span><span class="vs-prob prob-player" id="player-prob">0%</span></div>
            <div class="vs-text">VS</div>
            <div class="vs-item"><span class="vs-label">COMPUTER WIN %</span><span class="vs-prob prob-com" id="com-prob">0%</span></div>
        </div>
        <div class="pool-stats">
            <span>남은 후보: <b id="player-pool-size">30240</b></span>
            <span>남은 후보: <b id="com-pool-size">30240</b></span>
        </div>
    </div>
    <div id="terminal"></div>
    <div class="input-area"><input type="number" id="userInput" inputmode="numeric" placeholder="중복 없는 5자리 숫자 입력"></div>
    <div class="input-area"><button id="sendBtn">전송</button><button id="restartBtn">다시 시작</button></div>

    <script>
        let comPool = [], playerPool = [], userSecret = [], comSecret = [], gameState = "SETUP", round = 1;
        const terminal = document.getElementById('terminal'), userInput = document.getElementById('userInput'), sendBtn = document.getElementById('sendBtn'), restartBtn = document.getElementById('restartBtn');

        function log(msg, className = "") {
            const div = document.createElement('div'); div.className = "log-entry " + className; div.innerText = msg;
            terminal.appendChild(div); terminal.scrollTop = terminal.scrollHeight;
        }

        function calculateSB(target, guess) {
            let s = 0, b = 0;
            for (let i = 0; i < 5; i++) {
                for (let j = 0; j < 5; j++) {
                    if (target[i] === guess[j]) { if (i === j) s++; else b++; }
                }
            }
            return { s, b };
        }

        function generateFullPool() {
            const temp = [];
            for (let i = 0; i <= 9; i++) {
                for (let j = 0; j <= 9; j++) {
                    if (i === j) continue;
                    for (let k = 0; k <= 9; k++) {
                        if (i === k || j === k) continue;
                        for (let l = 0; l <= 9; l++) {
                            if (i === l || j === l || k === l) continue;
                            for (let m = 0; m <= 9; m++) {
                                if (i === m || j === m || k === m || l === m) continue;
                                temp.push([i, j, k, l, m]);
                            }
                        }
                    }
                }
            }
            return temp;
        }

        // --- 엔트로피(정보 획득량) 기반 추론 엔진 ---
        function getEntropyGuess() {
            if (comPool.length === 30240) return [0, 1, 2, 3, 4];
            if (comPool.length === 1) return comPool[0];

            // 연산 최적화: 후보군이 너무 많으면 일부 샘플링하여 엔트로피 계산
            const sampleSize = comPool.length > 500 ? 500 : comPool.length;
            const samples = [];
            const step = Math.floor(comPool.length / sampleSize);
            for(let i=0; i<sampleSize; i++) samples.push(comPool[i * step]);

            let bestGuess = comPool[0];
            let maxEntropy = -1;

            for (let i = 0; i < samples.length; i++) {
                let guess = samples[i];
                let scoreMap = {};

                for (let j = 0; j < samples.length; j++) {
                    let res = calculateSB(guess, samples[j]);
                    let key = `${res.s}${res.b}`;
                    scoreMap[key] = (scoreMap[key] || 0) + 1;
                }

                let entropy = 0;
                for (let key in scoreMap) {
                    let p = scoreMap[key] / samples.length;
                    entropy -= p * Math.log2(p);
                }

                if (entropy > maxEntropy) {
                    maxEntropy = entropy;
                    bestGuess = guess;
                }
            }
            return bestGuess;
        }

        function updateUI() {
            const pSize = playerPool.length, cSize = comPool.length;
            document.getElementById('player-pool-size').innerText = pSize;
            document.getElementById('com-pool-size').innerText = cSize;
            document.getElementById('player-prob').innerText = (pSize > 0 ? (100 / pSize).toFixed(2) : 0) + "%";
            document.getElementById('com-prob').innerText = (cSize > 0 ? (100 / cSize).toFixed(2) : 0) + "%";
        }

        function initGame() {
            terminal.innerHTML = ""; comPool = generateFullPool(); playerPool = generateFullPool();
            gameState = "SETUP"; round = 1; updateUI();
            log("System: 5자리 비밀 숫자를 입력하세요.", "system");
        }

        function startBattle(secretStr) {
            userSecret = secretStr.split('').map(Number);
            comSecret = []; const nums = [0,1,2,3,4,5,6,7,8,9];
            for(let i=0; i<5; i++) comSecret.push(nums.splice(Math.floor(Math.random()*nums.length), 1)[0]);
            gameState = "PLAY";
            log("System: 5자리 대결 시작! 컴퓨터가 추론을 시작합니다.", "system");
        }

        function processTurn(guessStr) {
            const pGuess = guessStr.split('').map(Number);
            const pRes = calculateSB(comSecret, pGuess);
            log(`R${round} [Player] ${guessStr} -> ${pRes.s}S ${pRes.b}B`, "player");
            if (pRes.s === 5) { log("결과: 플레이어 승리! 🎉", "system"); gameState = "END"; return; }
            playerPool = playerPool.filter(c => { const res = calculateSB(pGuess, c); return res.s === pRes.s && res.b === pRes.b; });

            const cGuess = getEntropyGuess();
            const cRes = calculateSB(userSecret, cGuess);
            log(`R${round} [Computer] ${cGuess.join('')} -> ${cRes.s}S ${cRes.b}B`, "computer");
            if (cRes.s === 5) { log(`결과: 컴퓨터 승리! 정답: ${userSecret.join('')}`, "system"); gameState = "END"; return; }
            comPool = comPool.filter(c => { const res = calculateSB(cGuess, c); return res.s === cRes.s && res.b === cRes.b; });

            round++; updateUI();
        }

        function handleInput() {
            const val = userInput.value;
            if (val.length !== 5 || new Set(val).size !== 5) { alert("중복 없는 5자리 숫자를 입력하세요."); return; }
            if (gameState === "SETUP") startBattle(val);
            else if (gameState === "PLAY") processTurn(val);
            userInput.value = ""; updateUI();
        }

        sendBtn.addEventListener('click', handleInput);
        userInput.addEventListener('keypress', (e) => { if (e.key === 'Enter') handleInput(); });
        restartBtn.addEventListener('click', initGame);
        initGame();
    </script>
</body>
</html>
