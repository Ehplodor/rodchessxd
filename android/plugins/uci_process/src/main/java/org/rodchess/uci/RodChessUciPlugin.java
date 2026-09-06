package org.rodchess.uci;

import android.util.Log;

import java.io.BufferedReader;
import java.io.IOException;
import java.io.InputStream;
import java.io.InputStreamReader;
import java.io.OutputStream;
import java.nio.charset.StandardCharsets;
import java.util.ArrayList;
import java.util.HashSet;
import java.util.List;
import java.util.Set;

import org.godotengine.godot.Godot;
import org.godotengine.godot.plugin.GodotPlugin;
import org.godotengine.godot.plugin.SignalInfo;
import org.godotengine.godot.plugin.UsedByGodot;

/**
 * Godot v2 Android plugin that launches a UCI chess engine (e.g. Stockfish) using
 * Android's ProcessBuilder / posix_spawn.
 *
 * This intentionally bypasses Godot's OS.execute* implementation, whose fork()-based
 * child creation is unreliable from Godot's multi-threaded Android process (the child
 * can be left as a zombie before exec, and no output ever reaches the engine pipes).
 *
 * Emitted signals (GDScript):
 *   uci_line(String)      : one line read from the engine's stdout
 *   uci_err(String)       : one line read from the engine's stderr
 *   engine_exited(int)    : the engine process terminated (exit code)
 */
public class RodChessUciPlugin extends GodotPlugin {

    private static final String TAG = "RodChessUci";

    private final Object lock = new Object();
    private Process process;
    private OutputStream stdin;

    public RodChessUciPlugin(Godot godot) {
        super(godot);
    }

    @Override
    public String getPluginName() {
        return "RodChessUci";
    }

    /**
     * Returns the native library directory of the application
     * (e.g. /data/app/.../lib/arm64). Files there are extracted by the Android
     * installer and are executable by the application's SELinux domain, unlike
     * files written into the app data directory on some ROMs.
     */
    @UsedByGodot
    public String getNativeLibraryDir() {
        try {
            if (getActivity() != null && getActivity().getApplicationInfo() != null) {
                return getActivity().getApplicationInfo().nativeLibraryDir;
            }
        } catch (Exception e) {
            Log.e(TAG, "getNativeLibraryDir failed", e);
        }
        return "";
    }

    @Override
    public Set<SignalInfo> getPluginSignals() {
        Set<SignalInfo> signals = new HashSet<>();
        signals.add(new SignalInfo("uci_line", String.class));
        signals.add(new SignalInfo("uci_err", String.class));
        signals.add(new SignalInfo("engine_exited", Integer.class));
        return signals;
    }

    @UsedByGodot
    public boolean startEngine(String path, String[] args) {
        synchronized (lock) {
            if (process != null && process.isAlive()) {
                Log.w(TAG, "startEngine: engine already running");
                return false;
            }
        }

        List<String> command = new ArrayList<>();
        command.add(path);
        if (args != null) {
            for (String arg : args) {
                command.add(arg);
            }
        }

        try {
            ProcessBuilder builder = new ProcessBuilder(command);
            builder.redirectErrorStream(false);
            Process started = builder.start();
            OutputStream out = started.getOutputStream();

            synchronized (lock) {
                process = started;
                stdin = out;
            }

            Log.i(TAG, "startEngine: launched " + path + " (args=" + (args == null ? 0 : args.length) + ")");

            Thread outThread = new Thread(() -> pump(started.getInputStream(), true), "uci-stdout");
            outThread.setDaemon(true);
            outThread.start();

            Thread errThread = new Thread(() -> pump(started.getErrorStream(), false), "uci-stderr");
            errThread.setDaemon(true);
            errThread.start();

            Thread exitThread = new Thread(() -> waitForExit(started), "uci-exit");
            exitThread.setDaemon(true);
            exitThread.start();

            return true;
        } catch (IOException e) {
            Log.e(TAG, "startEngine failed for " + path, e);
            return false;
        }
    }

    private void pump(InputStream stream, boolean stdout) {
        try (BufferedReader reader = new BufferedReader(new InputStreamReader(stream, StandardCharsets.UTF_8))) {
            String line;
            while ((line = reader.readLine()) != null) {
                if (stdout) {
                    emit("uci_line", line);
                } else {
                    emit("uci_err", line);
                }
            }
        } catch (IOException e) {
            // Stream closed during shutdown — expected.
        }
    }

    private void waitForExit(Process proc) {
        try {
            int exitCode = proc.waitFor();
            synchronized (lock) {
                if (process == proc) {
                    process = null;
                    stdin = null;
                }
            }
            Log.i(TAG, "engine exited with code " + exitCode);
            emit("engine_exited", exitCode);
        } catch (InterruptedException e) {
            Thread.currentThread().interrupt();
        }
    }

    @UsedByGodot
    public boolean sendCommand(String line) {
        OutputStream out;
        synchronized (lock) {
            out = stdin;
        }
        if (out == null) {
            return false;
        }
        try {
            out.write((line + "\n").getBytes(StandardCharsets.UTF_8));
            out.flush();
            return true;
        } catch (IOException e) {
            Log.e(TAG, "sendCommand failed", e);
            return false;
        }
    }

    @UsedByGodot
    public boolean isEngineRunning() {
        synchronized (lock) {
            return process != null && process.isAlive();
        }
    }

    @UsedByGodot
    public void stopEngine() {
        Process proc;
        synchronized (lock) {
            proc = process;
            process = null;
            stdin = null;
        }
        if (proc != null) {
            try {
                proc.destroy();
            } catch (Exception e) {
                Log.w(TAG, "stopEngine destroy failed", e);
            }
        }
    }

    private void emit(final String signal, final Object arg) {
        // Signals must be emitted on the host (main) thread.
        runOnHostThread(() -> emitSignal(signal, arg));
    }
}
