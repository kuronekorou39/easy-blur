(() => {
    'use strict';

    // ===== State =====
    const state = {
        image: null,
        originalWidth: 0,
        originalHeight: 0,
        displayWidth: 0,
        displayHeight: 0,
        scale: 1,
        mode: 'brush',
        blockSize: 15,
        brushSize: 30,
        history: [],
        redoStack: [],
        isDrawing: false,
        currentStroke: null,
        rectStart: null,
        fileName: 'image.png',
    };

    // ===== DOM Elements =====
    const $ = (sel) => document.querySelector(sel);
    const displayCanvas = $('#displayCanvas');
    const ctx = displayCanvas.getContext('2d', { willReadFrequently: true });
    const dropZone = $('#dropZone');
    const fileInput = $('#fileInput');
    const canvasContainer = $('#canvasContainer');
    const cursorOverlay = $('#cursorOverlay');
    const processingOverlay = $('#processingOverlay');

    const undoBtn = $('#undoBtn');
    const redoBtn = $('#redoBtn');
    const saveBtn = $('#saveBtn');
    const clearAllBtn = $('#clearAllBtn');
    const brushModeBtn = $('#brushModeBtn');
    const rectModeBtn = $('#rectModeBtn');
    const blockSizeSlider = $('#blockSizeSlider');
    const blockSizeValue = $('#blockSizeValue');
    const brushSizeSlider = $('#brushSizeSlider');
    const brushSizeValue = $('#brushSizeValue');
    const brushSizeSection = $('#brushSizeSection');
    const statusInfo = $('#statusInfo');
    const zoomInfo = $('#zoomInfo');

    // ===== Off-screen Canvases =====
    let originalCanvas, originalCtx;
    let mosaicCanvas, mosaicCtx;
    let maskCanvas, maskCtx;

    function createOffscreenCanvas(w, h) {
        const c = document.createElement('canvas');
        c.width = w;
        c.height = h;
        return c;
    }

    // ===== Image Loading =====
    function loadImage(file) {
        state.fileName = file.name.replace(/\.[^.]+$/, '') + '_mosaic.png';
        const reader = new FileReader();
        reader.onload = (e) => {
            const img = new Image();
            img.onload = () => {
                state.image = img;
                state.originalWidth = img.naturalWidth;
                state.originalHeight = img.naturalHeight;
                initCanvases();
            };
            img.src = e.target.result;
        };
        reader.readAsDataURL(file);
    }

    function initCanvases() {
        const img = state.image;
        const ow = state.originalWidth;
        const oh = state.originalHeight;

        // Calculate display size to fit in container
        const container = canvasContainer;
        const maxW = container.clientWidth - 48;
        const maxH = container.clientHeight - 48;
        const scaleW = maxW / ow;
        const scaleH = maxH / oh;
        state.scale = Math.min(scaleW, scaleH, 1);
        state.displayWidth = Math.round(ow * state.scale);
        state.displayHeight = Math.round(oh * state.scale);

        // Setup display canvas
        displayCanvas.width = state.displayWidth;
        displayCanvas.height = state.displayHeight;
        displayCanvas.style.display = 'block';
        displayCanvas.classList.toggle('brush-mode', state.mode === 'brush');
        displayCanvas.classList.toggle('rect-mode', state.mode === 'rect');

        // Create off-screen canvases at display resolution
        originalCanvas = createOffscreenCanvas(state.displayWidth, state.displayHeight);
        originalCtx = originalCanvas.getContext('2d', { willReadFrequently: true });
        originalCtx.drawImage(img, 0, 0, state.displayWidth, state.displayHeight);

        mosaicCanvas = createOffscreenCanvas(state.displayWidth, state.displayHeight);
        mosaicCtx = mosaicCanvas.getContext('2d', { willReadFrequently: true });

        maskCanvas = createOffscreenCanvas(state.displayWidth, state.displayHeight);
        maskCtx = maskCanvas.getContext('2d', { willReadFrequently: true });
        // Initialize mask to transparent (no mosaic)
        maskCtx.clearRect(0, 0, state.displayWidth, state.displayHeight);

        // Reset history
        state.history = [];
        state.redoStack = [];

        // Compute initial mosaic
        computeMosaic();

        // Render
        compositeDisplay();

        // Hide drop zone, enable buttons
        dropZone.style.display = 'none';
        saveBtn.disabled = false;
        updateButtons();

        // Status bar
        statusInfo.textContent = `${state.originalWidth} x ${state.originalHeight} px`;
        zoomInfo.textContent = `${Math.round(state.scale * 100)}%`;
    }

    // ===== Mosaic Engine =====
    function computeMosaic() {
        const w = state.displayWidth;
        const h = state.displayHeight;
        const bs = state.blockSize;

        mosaicCtx.drawImage(originalCanvas, 0, 0);
        const imageData = mosaicCtx.getImageData(0, 0, w, h);
        const data = imageData.data;

        for (let by = 0; by < h; by += bs) {
            for (let bx = 0; bx < w; bx += bs) {
                const bw = Math.min(bs, w - bx);
                const bh = Math.min(bs, h - by);
                const count = bw * bh;
                let rSum = 0, gSum = 0, bSum = 0;

                for (let y = by; y < by + bh; y++) {
                    for (let x = bx; x < bx + bw; x++) {
                        const i = (y * w + x) * 4;
                        rSum += data[i];
                        gSum += data[i + 1];
                        bSum += data[i + 2];
                    }
                }

                const rAvg = Math.round(rSum / count);
                const gAvg = Math.round(gSum / count);
                const bAvg = Math.round(bSum / count);

                for (let y = by; y < by + bh; y++) {
                    for (let x = bx; x < bx + bw; x++) {
                        const i = (y * w + x) * 4;
                        data[i] = rAvg;
                        data[i + 1] = gAvg;
                        data[i + 2] = bAvg;
                    }
                }
            }
        }

        mosaicCtx.putImageData(imageData, 0, 0);
    }

    function compositeDisplay() {
        const w = state.displayWidth;
        const h = state.displayHeight;

        // Draw original
        ctx.drawImage(originalCanvas, 0, 0);

        // Draw mosaic masked by the mask
        // Technique: draw mosaic onto a temp canvas clipped by mask
        const tempCanvas = createOffscreenCanvas(w, h);
        const tempCtx = tempCanvas.getContext('2d');

        // Draw mosaic
        tempCtx.drawImage(mosaicCanvas, 0, 0);

        // Apply mask: keep only where mask is white
        tempCtx.globalCompositeOperation = 'destination-in';
        tempCtx.drawImage(maskCanvas, 0, 0);

        // Draw masked mosaic on top of original
        ctx.drawImage(tempCanvas, 0, 0);
    }

    // ===== Mask Drawing =====
    function drawBrushOnMask(x, y, radius) {
        maskCtx.fillStyle = '#ffffff';
        maskCtx.beginPath();
        maskCtx.arc(x, y, radius, 0, Math.PI * 2);
        maskCtx.fill();
    }

    function drawLineOnMask(x1, y1, x2, y2, radius) {
        maskCtx.fillStyle = '#ffffff';
        maskCtx.strokeStyle = '#ffffff';
        maskCtx.lineWidth = radius * 2;
        maskCtx.lineCap = 'round';
        maskCtx.lineJoin = 'round';
        maskCtx.beginPath();
        maskCtx.moveTo(x1, y1);
        maskCtx.lineTo(x2, y2);
        maskCtx.stroke();
    }

    function drawRectOnMask(x, y, w, h) {
        maskCtx.fillStyle = '#ffffff';
        maskCtx.fillRect(x, y, w, h);
    }

    // ===== Action Replay =====
    function replayHistory() {
        maskCtx.clearRect(0, 0, state.displayWidth, state.displayHeight);
        for (const action of state.history) {
            replayAction(action);
        }
    }

    function replayAction(action) {
        if (action.type === 'brush') {
            const points = action.points;
            const radius = action.brushSize / 2;
            if (points.length === 1) {
                drawBrushOnMask(points[0].x, points[0].y, radius);
            } else {
                for (let i = 0; i < points.length - 1; i++) {
                    drawLineOnMask(points[i].x, points[i].y, points[i + 1].x, points[i + 1].y, radius);
                }
            }
        } else if (action.type === 'rect') {
            drawRectOnMask(action.x, action.y, action.w, action.h);
        }
    }

    // ===== Mouse -> Canvas Coordinates =====
    function getCanvasPos(e) {
        const rect = displayCanvas.getBoundingClientRect();
        return {
            x: e.clientX - rect.left,
            y: e.clientY - rect.top
        };
    }

    // ===== Brush Tool Handlers =====
    function brushDown(e) {
        const pos = getCanvasPos(e);
        state.isDrawing = true;
        state.currentStroke = {
            type: 'brush',
            points: [pos],
            brushSize: state.brushSize * (state.displayWidth / displayCanvas.getBoundingClientRect().width)
        };
        const radius = state.currentStroke.brushSize / 2;
        drawBrushOnMask(pos.x, pos.y, radius);
        compositeDisplay();
    }

    function brushMove(e) {
        if (!state.isDrawing || !state.currentStroke) return;
        const pos = getCanvasPos(e);
        const points = state.currentStroke.points;
        const lastPoint = points[points.length - 1];
        const radius = state.currentStroke.brushSize / 2;

        drawLineOnMask(lastPoint.x, lastPoint.y, pos.x, pos.y, radius);
        points.push(pos);
        compositeDisplay();
    }

    function brushUp() {
        if (!state.isDrawing || !state.currentStroke) return;
        state.isDrawing = false;
        if (state.currentStroke.points.length > 0) {
            state.history.push(state.currentStroke);
            state.redoStack = [];
        }
        state.currentStroke = null;
        updateButtons();
    }

    // ===== Rectangle Tool Handlers =====
    let rectPreviewActive = false;

    function rectDown(e) {
        const pos = getCanvasPos(e);
        state.rectStart = pos;
        rectPreviewActive = true;
    }

    function rectMove(e) {
        if (!rectPreviewActive || !state.rectStart) return;
        const pos = getCanvasPos(e);

        // Redraw with preview rectangle
        replayHistory();

        const rx = Math.min(state.rectStart.x, pos.x);
        const ry = Math.min(state.rectStart.y, pos.y);
        const rw = Math.abs(pos.x - state.rectStart.x);
        const rh = Math.abs(pos.y - state.rectStart.y);

        // Draw preview on mask (temporary)
        drawRectOnMask(rx, ry, rw, rh);
        compositeDisplay();

        // Draw rectangle outline on display
        ctx.strokeStyle = 'rgba(108, 92, 231, 0.8)';
        ctx.lineWidth = 2;
        ctx.setLineDash([6, 4]);
        ctx.strokeRect(rx, ry, rw, rh);
        ctx.setLineDash([]);
    }

    function rectUp(e) {
        if (!rectPreviewActive || !state.rectStart) return;
        const pos = getCanvasPos(e);
        rectPreviewActive = false;

        const rx = Math.min(state.rectStart.x, pos.x);
        const ry = Math.min(state.rectStart.y, pos.y);
        const rw = Math.abs(pos.x - state.rectStart.x);
        const rh = Math.abs(pos.y - state.rectStart.y);

        if (rw > 2 && rh > 2) {
            const action = { type: 'rect', x: rx, y: ry, w: rw, h: rh };
            state.history.push(action);
            state.redoStack = [];
            replayHistory();
            compositeDisplay();
        } else {
            // Too small, cancel
            replayHistory();
            compositeDisplay();
        }

        state.rectStart = null;
        updateButtons();
    }

    // ===== Unified Event Handlers =====
    function onPointerDown(e) {
        if (!state.image) return;
        e.preventDefault();
        if (state.mode === 'brush') brushDown(e);
        else rectDown(e);
    }

    function onPointerMove(e) {
        if (!state.image) return;
        e.preventDefault();

        // Update cursor overlay
        if (state.mode === 'brush') {
            const rect = displayCanvas.getBoundingClientRect();
            const cssScale = rect.width / state.displayWidth;
            const size = state.brushSize * cssScale;
            cursorOverlay.style.width = size + 'px';
            cursorOverlay.style.height = size + 'px';
            cursorOverlay.style.left = e.clientX + 'px';
            cursorOverlay.style.top = e.clientY + 'px';
        }

        if (state.mode === 'brush') brushMove(e);
        else rectMove(e);
    }

    function onPointerUp(e) {
        if (!state.image) return;
        if (state.mode === 'brush') brushUp();
        else rectUp(e);
    }

    // ===== Undo / Redo =====
    function undo() {
        if (state.history.length === 0) return;
        state.redoStack.push(state.history.pop());
        replayHistory();
        compositeDisplay();
        updateButtons();
    }

    function redo() {
        if (state.redoStack.length === 0) return;
        const action = state.redoStack.pop();
        state.history.push(action);
        replayAction(action);
        compositeDisplay();
        updateButtons();
    }

    function clearAll() {
        if (state.history.length === 0) return;
        // Store all current history as one undo point
        state.redoStack.push(...state.history.reverse());
        state.history = [];
        replayHistory();
        compositeDisplay();
        updateButtons();
    }

    // ===== Save =====
    async function saveImage() {
        if (!state.image) return;
        processingOverlay.style.display = 'flex';

        // Use setTimeout to let the overlay render
        await new Promise(r => setTimeout(r, 50));

        try {
            const ow = state.originalWidth;
            const oh = state.originalHeight;
            const scaleX = ow / state.displayWidth;
            const scaleY = oh / state.displayHeight;

            // Create full-resolution original
            const fullOriginal = createOffscreenCanvas(ow, oh);
            const fullOrigCtx = fullOriginal.getContext('2d');
            fullOrigCtx.drawImage(state.image, 0, 0, ow, oh);

            // Create full-resolution mosaic
            const fullMosaic = createOffscreenCanvas(ow, oh);
            const fullMosaicCtx = fullMosaic.getContext('2d', { willReadFrequently: true });
            fullMosaicCtx.drawImage(state.image, 0, 0, ow, oh);

            const bs = Math.max(1, Math.round(state.blockSize * scaleX));
            const imgData = fullMosaicCtx.getImageData(0, 0, ow, oh);
            const data = imgData.data;

            for (let by = 0; by < oh; by += bs) {
                for (let bx = 0; bx < ow; bx += bs) {
                    const bw = Math.min(bs, ow - bx);
                    const bh = Math.min(bs, oh - by);
                    const count = bw * bh;
                    let rS = 0, gS = 0, bS = 0;
                    for (let y = by; y < by + bh; y++) {
                        for (let x = bx; x < bx + bw; x++) {
                            const i = (y * ow + x) * 4;
                            rS += data[i]; gS += data[i + 1]; bS += data[i + 2];
                        }
                    }
                    const rA = Math.round(rS / count);
                    const gA = Math.round(gS / count);
                    const bA = Math.round(bS / count);
                    for (let y = by; y < by + bh; y++) {
                        for (let x = bx; x < bx + bw; x++) {
                            const i = (y * ow + x) * 4;
                            data[i] = rA; data[i + 1] = gA; data[i + 2] = bA;
                        }
                    }
                }
            }
            fullMosaicCtx.putImageData(imgData, 0, 0);

            // Create full-resolution mask by replaying history scaled
            const fullMask = createOffscreenCanvas(ow, oh);
            const fullMaskCtx = fullMask.getContext('2d');
            fullMaskCtx.scale(scaleX, scaleY);

            for (const action of state.history) {
                if (action.type === 'brush') {
                    const pts = action.points;
                    const radius = action.brushSize / 2;
                    fullMaskCtx.fillStyle = '#ffffff';
                    fullMaskCtx.strokeStyle = '#ffffff';
                    fullMaskCtx.lineWidth = radius * 2;
                    fullMaskCtx.lineCap = 'round';
                    fullMaskCtx.lineJoin = 'round';
                    if (pts.length === 1) {
                        fullMaskCtx.beginPath();
                        fullMaskCtx.arc(pts[0].x, pts[0].y, radius, 0, Math.PI * 2);
                        fullMaskCtx.fill();
                    } else {
                        for (let i = 0; i < pts.length - 1; i++) {
                            fullMaskCtx.beginPath();
                            fullMaskCtx.moveTo(pts[i].x, pts[i].y);
                            fullMaskCtx.lineTo(pts[i + 1].x, pts[i + 1].y);
                            fullMaskCtx.stroke();
                        }
                    }
                } else if (action.type === 'rect') {
                    fullMaskCtx.fillStyle = '#ffffff';
                    fullMaskCtx.fillRect(action.x, action.y, action.w, action.h);
                }
            }

            // Composite at full resolution
            const outputCanvas = createOffscreenCanvas(ow, oh);
            const outCtx = outputCanvas.getContext('2d');
            outCtx.drawImage(fullOriginal, 0, 0);

            const tempC = createOffscreenCanvas(ow, oh);
            const tempCtx = tempC.getContext('2d');
            tempCtx.drawImage(fullMosaic, 0, 0);
            tempCtx.globalCompositeOperation = 'destination-in';
            tempCtx.drawImage(fullMask, 0, 0);
            outCtx.drawImage(tempC, 0, 0);

            // Export
            outputCanvas.toBlob((blob) => {
                const url = URL.createObjectURL(blob);
                const a = document.createElement('a');
                a.href = url;
                a.download = state.fileName;
                document.body.appendChild(a);
                a.click();
                document.body.removeChild(a);
                URL.revokeObjectURL(url);
                processingOverlay.style.display = 'none';
            }, 'image/png');
        } catch (err) {
            console.error('Save failed:', err);
            processingOverlay.style.display = 'none';
            alert('保存に失敗しました: ' + err.message);
        }
    }

    // ===== UI Updates =====
    function updateButtons() {
        undoBtn.disabled = state.history.length === 0;
        redoBtn.disabled = state.redoStack.length === 0;
        clearAllBtn.disabled = state.history.length === 0;
    }

    function setMode(mode) {
        state.mode = mode;
        brushModeBtn.classList.toggle('active', mode === 'brush');
        rectModeBtn.classList.toggle('active', mode === 'rect');
        brushSizeSection.style.display = mode === 'brush' ? '' : 'none';
        displayCanvas.classList.toggle('brush-mode', mode === 'brush');
        displayCanvas.classList.toggle('rect-mode', mode === 'rect');
        cursorOverlay.style.display = mode === 'brush' && state.image ? '' : 'none';
    }

    // ===== Event Bindings =====

    // File drop
    dropZone.addEventListener('dragover', (e) => {
        e.preventDefault();
        dropZone.classList.add('drag-over');
    });

    dropZone.addEventListener('dragleave', () => {
        dropZone.classList.remove('drag-over');
    });

    dropZone.addEventListener('drop', (e) => {
        e.preventDefault();
        dropZone.classList.remove('drag-over');
        const file = e.dataTransfer.files[0];
        if (file && file.type.startsWith('image/')) {
            loadImage(file);
        }
    });

    // Also allow drop on the entire canvas area when image is loaded
    canvasContainer.addEventListener('dragover', (e) => {
        e.preventDefault();
    });

    canvasContainer.addEventListener('drop', (e) => {
        e.preventDefault();
        const file = e.dataTransfer.files[0];
        if (file && file.type.startsWith('image/')) {
            loadImage(file);
        }
    });

    $('#fileSelectBtn').addEventListener('click', () => fileInput.click());
    fileInput.addEventListener('change', (e) => {
        if (e.target.files[0]) {
            loadImage(e.target.files[0]);
            fileInput.value = '';
        }
    });

    // Canvas pointer events
    displayCanvas.addEventListener('pointerdown', onPointerDown);
    displayCanvas.addEventListener('pointermove', onPointerMove);
    displayCanvas.addEventListener('pointerup', onPointerUp);
    displayCanvas.addEventListener('pointerleave', (e) => {
        cursorOverlay.style.display = 'none';
        onPointerUp(e);
    });
    displayCanvas.addEventListener('pointerenter', () => {
        if (state.mode === 'brush' && state.image) {
            cursorOverlay.style.display = '';
        }
    });

    // Prevent context menu on canvas
    displayCanvas.addEventListener('contextmenu', (e) => e.preventDefault());

    // Mode buttons
    brushModeBtn.addEventListener('click', () => setMode('brush'));
    rectModeBtn.addEventListener('click', () => setMode('rect'));

    // Sliders
    let blockSizeTimeout;
    blockSizeSlider.addEventListener('input', (e) => {
        state.blockSize = parseInt(e.target.value);
        blockSizeValue.textContent = state.blockSize;

        clearTimeout(blockSizeTimeout);
        blockSizeTimeout = setTimeout(() => {
            if (state.image) {
                computeMosaic();
                replayHistory();
                compositeDisplay();
            }
        }, 80);
    });

    brushSizeSlider.addEventListener('input', (e) => {
        state.brushSize = parseInt(e.target.value);
        brushSizeValue.textContent = state.brushSize;
    });

    // Header buttons
    undoBtn.addEventListener('click', undo);
    redoBtn.addEventListener('click', redo);
    saveBtn.addEventListener('click', saveImage);
    clearAllBtn.addEventListener('click', clearAll);

    // Keyboard shortcuts
    document.addEventListener('keydown', (e) => {
        // Ignore if typing in an input
        if (e.target.tagName === 'INPUT' || e.target.tagName === 'TEXTAREA') return;

        if (e.ctrlKey || e.metaKey) {
            if (e.key === 'z' && !e.shiftKey) {
                e.preventDefault();
                undo();
            } else if (e.key === 'y' || (e.key === 'z' && e.shiftKey)) {
                e.preventDefault();
                redo();
            } else if (e.key === 's') {
                e.preventDefault();
                saveImage();
            }
        } else {
            if (e.key === 'b' || e.key === 'B') setMode('brush');
            if (e.key === 'r' || e.key === 'R') setMode('rect');
            if (e.key === '[') {
                state.brushSize = Math.max(5, state.brushSize - 5);
                brushSizeSlider.value = state.brushSize;
                brushSizeValue.textContent = state.brushSize;
            }
            if (e.key === ']') {
                state.brushSize = Math.min(150, state.brushSize + 5);
                brushSizeSlider.value = state.brushSize;
                brushSizeValue.textContent = state.brushSize;
            }
        }
    });

    // Window resize
    let resizeTimeout;
    window.addEventListener('resize', () => {
        clearTimeout(resizeTimeout);
        resizeTimeout = setTimeout(() => {
            if (state.image) initCanvases();
        }, 200);
    });

    // Initial mode setup
    setMode('brush');
})();
