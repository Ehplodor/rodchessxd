// uci_worker_bridge.js - Pont Web Worker Stockfish pour RodChessXD HTML5 / PWA
(function() {
    window.RodChessUci = {
        worker: null,
        callback: null,
        pendingCommands: [],
        ready: false,

        init: function(godotCallback) {
            this.callback = godotCallback;
            if (this.worker) {
                console.log('[RodChessUci] Worker deja initialise.');
                return true;
            }

            console.log('[RodChessUci] Demarrage du Web Worker Stockfish...');
            try {
                this.worker = new Worker('stockfish.js');
                var self = this;

                this.worker.onmessage = function(event) {
                    var line = typeof event.data === 'string' ? event.data : (event.data && event.data.data ? event.data.data : '');
                    if (!line) return;

                    if (line.indexOf('uciok') !== -1 || line.indexOf('readyok') !== -1) {
                        self.ready = true;
                    }

                    if (self.callback) {
                        try {
                            self.callback(line);
                        } catch(e) {
                            console.error('[RodChessUci] Erreur callback Godot:', e);
                        }
                    }
                };

                this.worker.onerror = function(err) {
                    console.error('[RodChessUci] Erreur Stockfish Worker:', err);
                };

                while (this.pendingCommands.length > 0) {
                    var cmd = this.pendingCommands.shift();
                    this.sendCommand(cmd);
                }

                return true;
            } catch(e) {
                console.error('[RodChessUci] Echec creation Worker Stockfish:', e);
                return false;
            }
        },

        sendCommand: function(cmd) {
            if (!this.worker) {
                this.pendingCommands.push(cmd);
                return;
            }
            try {
                this.worker.postMessage(cmd);
            } catch(e) {
                console.error('[RodChessUci] Echec envoi commande:', cmd, e);
            }
        },

        stopEngine: function() {
            if (this.worker) {
                this.sendCommand('stop');
            }
        },

        isReady: function() {
            return this.worker !== null;
        }
    };
    console.log('[RodChessUci] Module de pont pret.');

    // Persistance durable du stockage Web (immunise IndexedDB contre l'eviction Safari 7j et Chrome basse memoire)
    if (typeof navigator !== 'undefined' && navigator.storage && navigator.storage.persist) {
        navigator.storage.persist().then(function(persistent) {
            console.log('[RodChessStorage] Persistance durable :', persistent ? 'accordee' : 'non accordee (temporaire)');
        }).catch(function(err) {
            console.warn('[RodChessStorage] Erreur demande persistance :', err);
        });
    }

    // Journalisation du cycle de vie lors du masquage ou de la fermeture
    function onStorageLifecycleEvent(evt) {
        console.log('[RodChessStorage] Evenement de cycle de vie Web :', evt.type);
    }
    if (typeof window !== 'undefined') {
        window.addEventListener('pagehide', onStorageLifecycleEvent);
        window.addEventListener('beforeunload', onStorageLifecycleEvent);
    }
    if (typeof document !== 'undefined') {
        document.addEventListener('visibilitychange', function() {
            if (document.visibilityState === 'hidden') {
                onStorageLifecycleEvent({ type: 'visibilitychange:hidden' });
            }
        });
    }
})();
