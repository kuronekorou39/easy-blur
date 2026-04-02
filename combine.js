(() => {
    'use strict';

    // ===== State =====
    const state = {
        images: [],        // { img: Image, name: string, naturalWidth, naturalHeight }
        rows: 2,
        rowCounts: [],     // e.g. [6, 5] for 11 images in 2 rows
        gap: 8,
        padding: 0,
        bgColor: '#ffffff',
        alignMode: 'equal-width',  // 'equal-width' | 'equal-height'
        rowHeight: 800,
    };

    // ===== DOM =====
    const $ = (s) => document.querySelector(s);
    const dropZone = $('#dropZone');
    const fileInput = $('#fileInput');
    const imageList = $('#imageList');
    const addMore = $('#addMore');
    const previewArea = $('#previewArea');
    const previewCanvas = $('#previewCanvas');
    const previewCtx = previewCanvas.getContext('2d');
    const processingOverlay = $('#processingOverlay');

    const exportBtn = $('#exportBtn');
    const clearBtn = $('#clearBtn');
    const imageCount = $('#imageCount');
    const rowsValue = $('#rowsValue');
    const gapSlider = $('#gapSlider');
    const gapValue = $('#gapValue');
    const paddingSlider = $('#paddingSlider');
    const paddingValue = $('#paddingValue');
    const rowHeightSlider = $('#rowHeightSlider');
    const rowHeightValue = $('#rowHeightValue');
    const alignMode = $('#alignMode');
    const rowDistribution = $('#rowDistribution');
    const outputSizeInfo = $('#outputSizeInfo');

    // ===== Image Loading =====
    function loadFiles(files) {
        const imageFiles = Array.from(files).filter(f => f.type.startsWith('image/'));
        if (imageFiles.length === 0) return;

        let loaded = 0;
        for (const file of imageFiles) {
            const reader = new FileReader();
            reader.onload = (e) => {
                const img = new Image();
                img.onload = () => {
                    state.images.push({
                        img,
                        name: file.name,
                        naturalWidth: img.naturalWidth,
                        naturalHeight: img.naturalHeight,
                    });
                    loaded++;
                    if (loaded === imageFiles.length) {
                        onImagesChanged();
                    }
                };
                img.src = e.target.result;
            };
            reader.readAsDataURL(file);
        }
    }

    function removeImage(index) {
        state.images.splice(index, 1);
        onImagesChanged();
    }

    function onImagesChanged() {
        const n = state.images.length;
        imageCount.textContent = n > 0 ? `${n}枚` : '';

        if (n === 0) {
            dropZone.style.display = '';
            imageList.style.display = 'none';
            addMore.style.display = 'none';
            previewArea.style.display = 'none';
            exportBtn.disabled = true;
            clearBtn.disabled = true;
            outputSizeInfo.textContent = '';
            rowDistribution.innerHTML = '';
            return;
        }

        dropZone.style.display = 'none';
        imageList.style.display = '';
        addMore.style.display = '';
        previewArea.style.display = '';
        exportBtn.disabled = false;
        clearBtn.disabled = false;

        distributeRows();
        renderThumbnails();
        renderPreview();
    }

    // ===== Row Distribution =====
    function distributeRows() {
        const n = state.images.length;
        const rows = Math.min(state.rows, n);
        const counts = [];
        const base = Math.floor(n / rows);
        let remainder = n % rows;
        for (let i = 0; i < rows; i++) {
            counts.push(base + (remainder > 0 ? 1 : 0));
            if (remainder > 0) remainder--;
        }
        state.rowCounts = counts;
        renderRowDistribution();
    }

    function renderRowDistribution() {
        rowDistribution.innerHTML = '';
        state.rowCounts.forEach((count, i) => {
            const item = document.createElement('div');
            item.className = 'row-dist-item';
            item.innerHTML = `
                <span class="row-label">行${i + 1}</span>
                <div class="row-dist-stepper">
                    <button data-row="${i}" data-dir="-1">-</button>
                    <span>${count}</span>
                    <button data-row="${i}" data-dir="1">+</button>
                </div>
                <span>${count}枚</span>
            `;
            rowDistribution.appendChild(item);
        });

        // Bind stepper events
        rowDistribution.querySelectorAll('button').forEach(btn => {
            btn.addEventListener('click', () => {
                const row = parseInt(btn.dataset.row);
                const dir = parseInt(btn.dataset.dir);
                adjustRowCount(row, dir);
            });
        });
    }

    function adjustRowCount(rowIndex, delta) {
        const counts = state.rowCounts;
        const newVal = counts[rowIndex] + delta;
        if (newVal < 1) return;

        // Find a neighbor to take from / give to
        const total = counts.reduce((a, b) => a + b, 0);
        if (delta > 0) {
            // Need to take from another row
            for (let i = 0; i < counts.length; i++) {
                if (i !== rowIndex && counts[i] > 1) {
                    counts[i]--;
                    counts[rowIndex]++;
                    break;
                }
            }
        } else {
            // Give to adjacent row
            const neighbor = rowIndex < counts.length - 1 ? rowIndex + 1 : rowIndex - 1;
            if (neighbor >= 0 && neighbor < counts.length) {
                counts[rowIndex]--;
                counts[neighbor]++;
            }
        }

        renderRowDistribution();
        renderThumbnails();
        renderPreview();
    }

    // ===== Thumbnails =====
    let dragSrcIndex = null;

    function renderThumbnails() {
        imageList.innerHTML = '';
        let globalIndex = 0;

        for (let r = 0; r < state.rowCounts.length; r++) {
            const sep = document.createElement('div');
            sep.className = 'row-separator';
            sep.textContent = `行 ${r + 1}`;
            imageList.appendChild(sep);

            for (let c = 0; c < state.rowCounts[r]; c++) {
                if (globalIndex >= state.images.length) break;
                const idx = globalIndex;
                const entry = state.images[idx];

                const item = document.createElement('div');
                item.className = 'thumb-item';
                item.draggable = true;
                item.dataset.index = idx;

                const img = document.createElement('img');
                img.src = entry.img.src;
                item.appendChild(img);

                const indexLabel = document.createElement('div');
                indexLabel.className = 'thumb-index';
                indexLabel.textContent = idx + 1;
                item.appendChild(indexLabel);

                const removeBtn = document.createElement('button');
                removeBtn.className = 'thumb-remove';
                removeBtn.textContent = '\u00d7';
                removeBtn.addEventListener('click', (e) => {
                    e.stopPropagation();
                    removeImage(idx);
                });
                item.appendChild(removeBtn);

                // Context menu to remove
                item.addEventListener('contextmenu', (e) => {
                    e.preventDefault();
                    removeImage(idx);
                });

                // Drag & drop reorder
                item.addEventListener('dragstart', (e) => {
                    dragSrcIndex = idx;
                    item.classList.add('dragging');
                    e.dataTransfer.effectAllowed = 'move';
                });
                item.addEventListener('dragend', () => {
                    item.classList.remove('dragging');
                    dragSrcIndex = null;
                    document.querySelectorAll('.drag-over-item').forEach(el => el.classList.remove('drag-over-item'));
                });
                item.addEventListener('dragover', (e) => {
                    e.preventDefault();
                    if (dragSrcIndex === null) return;
                    e.dataTransfer.dropEffect = 'move';
                    item.classList.add('drag-over-item');
                });
                item.addEventListener('dragleave', () => {
                    item.classList.remove('drag-over-item');
                });
                item.addEventListener('drop', (e) => {
                    e.preventDefault();
                    item.classList.remove('drag-over-item');
                    if (dragSrcIndex === null || dragSrcIndex === idx) return;
                    const moved = state.images.splice(dragSrcIndex, 1)[0];
                    state.images.splice(idx, 0, moved);
                    dragSrcIndex = null;
                    renderThumbnails();
                    renderPreview();
                });

                imageList.appendChild(item);
                globalIndex++;
            }
        }
    }

    // ===== Layout Calculation =====
    function computeLayout() {
        const { images, rowCounts, gap, padding, alignMode, rowHeight } = state;
        if (images.length === 0) return null;

        const rows = [];
        let idx = 0;

        for (let r = 0; r < rowCounts.length; r++) {
            const rowImages = [];
            for (let c = 0; c < rowCounts[r] && idx < images.length; c++) {
                rowImages.push(images[idx++]);
                }
            rows.push(rowImages);
        }

        if (alignMode === 'equal-width') {
            return layoutEqualWidth(rows, gap, padding, rowHeight);
        } else {
            return layoutEqualHeight(rows, gap, padding, rowHeight);
        }
    }

    function layoutEqualWidth(rows, gap, padding, baseRowHeight) {
        // For equal-width mode:
        // 1. Compute each row's width if all images were at baseRowHeight
        // 2. Find the max width
        // 3. Scale each row's height so its total width = maxWidth

        const rowInfos = rows.map(rowImages => {
            const aspectSum = rowImages.reduce((sum, e) => sum + e.naturalWidth / e.naturalHeight, 0);
            return { images: rowImages, aspectSum };
        });

        // Find the target width: use the width of the widest row at baseRowHeight
        let maxWidth = 0;
        for (const ri of rowInfos) {
            const w = ri.aspectSum * baseRowHeight + (ri.images.length - 1) * gap;
            if (w > maxWidth) maxWidth = w;
        }

        const totalWidth = maxWidth + padding * 2;
        const rowLayouts = [];
        let totalHeight = padding;

        for (const ri of rowInfos) {
            const innerWidth = maxWidth;
            const gapsWidth = (ri.images.length - 1) * gap;
            const h = (innerWidth - gapsWidth) / ri.aspectSum;

            const imageLayouts = [];
            let x = padding;
            for (const entry of ri.images) {
                const w = entry.naturalWidth / entry.naturalHeight * h;
                imageLayouts.push({ entry, x, y: totalHeight, w, h });
                x += w + gap;
            }
            rowLayouts.push(imageLayouts);
            totalHeight += h + gap;
        }
        totalHeight += padding - gap; // remove last gap, add bottom padding

        return {
            width: Math.round(totalWidth),
            height: Math.round(totalHeight),
            rows: rowLayouts,
        };
    }

    function layoutEqualHeight(rows, gap, padding, rowHeight) {
        // All rows have the same height = rowHeight
        // Rows may have different widths, centered in the output

        const rowLayouts = [];
        let maxWidth = 0;

        for (const rowImages of rows) {
            const imageLayouts = [];
            let x = 0;
            for (const entry of rowImages) {
                const w = entry.naturalWidth / entry.naturalHeight * rowHeight;
                imageLayouts.push({ entry, x, y: 0, w, h: rowHeight });
                x += w + gap;
            }
            const rowWidth = x - gap;
            if (rowWidth > maxWidth) maxWidth = rowWidth;
            rowLayouts.push(imageLayouts);
        }

        const totalWidth = maxWidth + padding * 2;
        let y = padding;

        for (const row of rowLayouts) {
            const rowWidth = row.reduce((sum, il) => sum + il.w, 0) + (row.length - 1) * gap;
            const offsetX = padding + (maxWidth - rowWidth) / 2;
            for (const il of row) {
                il.x += offsetX;
                il.y = y;
            }
            y += rowHeight + gap;
        }
        const totalHeight = y - gap + padding;

        return {
            width: Math.round(totalWidth),
            height: Math.round(totalHeight),
            rows: rowLayouts,
        };
    }

    // ===== Render Preview =====
    let renderRAF = null;

    function renderPreview() {
        if (renderRAF) cancelAnimationFrame(renderRAF);
        renderRAF = requestAnimationFrame(() => {
            const layout = computeLayout();
            if (!layout) return;

            previewCanvas.width = layout.width;
            previewCanvas.height = layout.height;

            // Background
            if (state.bgColor === 'transparent') {
                previewCtx.clearRect(0, 0, layout.width, layout.height);
                // Draw checkerboard for transparent preview
                const size = 16;
                for (let y = 0; y < layout.height; y += size) {
                    for (let x = 0; x < layout.width; x += size) {
                        previewCtx.fillStyle = ((x / size + y / size) % 2 === 0) ? '#ccc' : '#fff';
                        previewCtx.fillRect(x, y, size, size);
                    }
                }
            } else {
                previewCtx.fillStyle = state.bgColor;
                previewCtx.fillRect(0, 0, layout.width, layout.height);
            }

            // Draw images
            for (const row of layout.rows) {
                for (const il of row) {
                    previewCtx.drawImage(il.entry.img, il.x, il.y, il.w, il.h);
                }
            }

            outputSizeInfo.textContent = `出力: ${layout.width} x ${layout.height} px`;
        });
    }

    // ===== Export =====
    async function exportImage() {
        const layout = computeLayout();
        if (!layout) return;

        processingOverlay.style.display = 'flex';
        await new Promise(r => setTimeout(r, 50));

        try {
            const canvas = document.createElement('canvas');
            canvas.width = layout.width;
            canvas.height = layout.height;
            const ctx2 = canvas.getContext('2d');

            if (state.bgColor === 'transparent') {
                ctx2.clearRect(0, 0, layout.width, layout.height);
            } else {
                ctx2.fillStyle = state.bgColor;
                ctx2.fillRect(0, 0, layout.width, layout.height);
            }

            for (const row of layout.rows) {
                for (const il of row) {
                    ctx2.drawImage(il.entry.img, il.x, il.y, il.w, il.h);
                }
            }

            canvas.toBlob((blob) => {
                const url = URL.createObjectURL(blob);
                const a = document.createElement('a');
                a.href = url;
                a.download = 'combined.png';
                document.body.appendChild(a);
                a.click();
                document.body.removeChild(a);
                URL.revokeObjectURL(url);
                processingOverlay.style.display = 'none';
            }, 'image/png');
        } catch (err) {
            console.error('Export failed:', err);
            processingOverlay.style.display = 'none';
            alert('書き出しに失敗しました: ' + err.message);
        }
    }

    // ===== Event Bindings =====

    // File drop
    dropZone.addEventListener('dragover', (e) => { e.preventDefault(); dropZone.classList.add('drag-over'); });
    dropZone.addEventListener('dragleave', () => dropZone.classList.remove('drag-over'));
    dropZone.addEventListener('drop', (e) => { e.preventDefault(); dropZone.classList.remove('drag-over'); loadFiles(e.dataTransfer.files); });

    // Also allow drop on the main area for adding more
    document.querySelector('.main-area').addEventListener('dragover', (e) => e.preventDefault());
    document.querySelector('.main-area').addEventListener('drop', (e) => {
        e.preventDefault();
        if (e.dataTransfer.files.length > 0 && e.dataTransfer.files[0].type.startsWith('image/')) {
            loadFiles(e.dataTransfer.files);
        }
    });

    $('#fileSelectBtn').addEventListener('click', () => fileInput.click());
    $('#addMoreBtn').addEventListener('click', () => fileInput.click());
    fileInput.addEventListener('change', (e) => {
        if (e.target.files.length > 0) {
            loadFiles(e.target.files);
            fileInput.value = '';
        }
    });

    // Header buttons
    exportBtn.addEventListener('click', exportImage);
    clearBtn.addEventListener('click', () => { state.images = []; onImagesChanged(); });

    // Rows stepper
    $('#rowsDec').addEventListener('click', () => {
        if (state.rows > 1) {
            state.rows--;
            rowsValue.textContent = state.rows;
            if (state.images.length > 0) { distributeRows(); renderThumbnails(); renderPreview(); }
        }
    });
    $('#rowsInc').addEventListener('click', () => {
        if (state.rows < state.images.length && state.rows < 10) {
            state.rows++;
            rowsValue.textContent = state.rows;
            if (state.images.length > 0) { distributeRows(); renderThumbnails(); renderPreview(); }
        }
    });

    // Sliders
    gapSlider.addEventListener('input', (e) => {
        state.gap = parseInt(e.target.value);
        gapValue.textContent = state.gap + 'px';
        renderPreview();
    });
    paddingSlider.addEventListener('input', (e) => {
        state.padding = parseInt(e.target.value);
        paddingValue.textContent = state.padding + 'px';
        renderPreview();
    });
    rowHeightSlider.addEventListener('input', (e) => {
        state.rowHeight = parseInt(e.target.value);
        rowHeightValue.textContent = state.rowHeight + 'px';
        renderPreview();
    });

    // Align mode
    alignMode.addEventListener('change', (e) => {
        state.alignMode = e.target.value;
        renderPreview();
    });

    // Background color
    document.querySelectorAll('.color-btn').forEach(btn => {
        btn.addEventListener('click', () => {
            document.querySelectorAll('.color-btn').forEach(b => b.classList.remove('active'));
            btn.classList.add('active');
            state.bgColor = btn.dataset.color;
            renderPreview();
        });
    });
    $('#customColor').addEventListener('input', (e) => {
        document.querySelectorAll('.color-btn').forEach(b => b.classList.remove('active'));
        state.bgColor = e.target.value;
        renderPreview();
    });

    // Keyboard shortcuts
    document.addEventListener('keydown', (e) => {
        if ((e.ctrlKey || e.metaKey) && e.key === 's') {
            e.preventDefault();
            exportImage();
        }
    });
})();
