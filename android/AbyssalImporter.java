package org.abyssal.engine;

import android.app.Activity;
import android.content.Intent;
import android.net.Uri;
import org.godotengine.godot.Godot;
import org.godotengine.godot.plugin.GodotPlugin;
import org.godotengine.godot.plugin.SignalInfo;
import org.godotengine.godot.plugin.UsedByGodot;
import java.io.*;
import java.util.*;
import java.util.zip.ZipFile;

/** Offline transport for the shared data-only JAR decoder. No network permission. */
public final class AbyssalImporter extends GodotPlugin {
    private static final int PICK = 4821, CONVERT = 4822, SAVE_PICK = 4823, SAVE_WRITE = 4824, IMAGE_PICK = 4825;
    private static final int LIMIT = 128 * 1024 * 1024, SAVE_LIMIT = 8 * 1024 * 1024;
    private volatile int generation;
    private volatile boolean busy;
    private File input;
    /** Export payload waiting for the destination the document picker returns. */
    private volatile String pendingSave;

    public AbyssalImporter(Godot godot) { super(godot); }
    @Override public String getPluginName() { return "AbyssalImporter"; }
    @Override public Set<SignalInfo> getPluginSignals() {
        return new HashSet<>(Arrays.asList(new SignalInfo("progress", String.class),
            new SignalInfo("selected", String.class), new SignalInfo("failed", String.class),
            new SignalInfo("busy_changed", Boolean.class),
            new SignalInfo("save_selected", String.class),
            new SignalInfo("save_exported", String.class),
            new SignalInfo("save_failed", String.class),
            new SignalInfo("image_selected", String.class),
            new SignalInfo("image_failed", String.class)));
    }
    /** A PNG for the Mods page, staged into cache like a chosen save. */
    @UsedByGodot public void choose_image() {
        getActivity().runOnUiThread(() -> {
            Intent intent = new Intent(Intent.ACTION_OPEN_DOCUMENT);
            intent.addCategory(Intent.CATEGORY_OPENABLE);
            intent.setType("image/*");
            try { getActivity().startActivityForResult(intent, IMAGE_PICK); }
            catch (Exception e) { emitSignal("image_failed", "No file picker is available: " + e.getMessage()); }
        });
    }
    private void receiveImage(Uri uri) {
        new Thread(() -> {
            File staged = null;
            try {
                staged = File.createTempFile("abyssal-image-", ".png", getActivity().getCacheDir());
                try (InputStream src = getActivity().getContentResolver().openInputStream(uri);
                     OutputStream dst = new FileOutputStream(staged)) {
                    byte[] buffer = new byte[65536]; int count; long total = 0;
                    while ((count = src.read(buffer)) != -1) {
                        total += count;
                        if (total > LIMIT) throw new IOException("Image exceeds 128 MiB.");
                        dst.write(buffer, 0, count);
                    }
                }
                final File ready = staged;
                staged = null;
                getActivity().runOnUiThread(() -> emitSignal("image_selected", ready.getAbsolutePath()));
            } catch (Exception e) {
                final String reason = String.valueOf(e.getMessage());
                getActivity().runOnUiThread(() -> emitSignal("image_failed", "Cannot read this image: " + reason));
            } finally { if (staged != null) staged.delete(); }
        }, "abyssal-image-import").start();
    }
    @Override public void onMainActivityResult(int request, int result, Intent data) {
        if (request == IMAGE_PICK) {
            if (result == Activity.RESULT_OK && data != null && data.getData() != null) receiveImage(data.getData());
            return;
        }
        if (request == SAVE_PICK) {
            if (result == Activity.RESULT_OK && data != null && data.getData() != null) receiveSave(data.getData());
            return;
        }
        if (request == SAVE_WRITE) {
            if (result == Activity.RESULT_OK && data != null && data.getData() != null) deliverSave(data.getData());
            else pendingSave = null;
            return;
        }
        if (request == CONVERT) {
            if (result == Activity.RESULT_OK && data != null && data.hasExtra("selected"))
                finish(generation, "selected", data.getStringExtra("selected"));
            else finish(generation, "failed", data != null && data.hasExtra("failed")
                ? data.getStringExtra("failed") : "Import cancelled or Android System WebView stopped. Try again or select a prepared .abyss pack.");
            return;
        }
        if (request != PICK || result != Activity.RESULT_OK || data == null || busy) return;
        final Uri uri = data.getData();
        busy = true;
        emitSignal("busy_changed", true);
        final int token = ++generation;
        emitSignal("progress", "Reading your local file…");
        new Thread(() -> {
            File selected = null;
            try {
                selected = File.createTempFile("abyssal-input-", ".zip", getActivity().getCacheDir());
                try (InputStream src = getActivity().getContentResolver().openInputStream(uri);
                     OutputStream dst = new FileOutputStream(selected)) {
                    byte[] buffer = new byte[65536]; int count; long total = 0;
                    while ((count = src.read(buffer)) != -1) {
                        if (token != generation) return;
                        total += count;
                        if (total > LIMIT) throw new IOException("File exceeds 128 MiB.");
                        dst.write(buffer, 0, count);
                    }
                }
                boolean pack;
                try (ZipFile zip = new ZipFile(selected)) { pack = zip.getEntry("pack.json") != null; }
                if (!pack && selected.length() > 16 * 1024 * 1024) throw new IOException("JAR exceeds 16 MiB.");
                final File ready = selected;
                getActivity().runOnUiThread(() -> {
                    if (token != generation) { ready.delete(); return; }
                    if (pack) finish(token, "selected", ready.getAbsolutePath());
                    else { input = ready; startConverter(token); }
                });
                selected = null;
            } catch (Exception e) { finish(token, "failed", "Cannot import this file: " + e.getMessage()); }
            finally { if (selected != null) selected.delete(); }
        }, "abyssal-import").start();
    }

    private void startConverter(int token) {
        if (token != generation) return;
        Intent intent = new Intent(getActivity(), AbyssalImportActivity.class);
        intent.putExtra("input", input.getAbsolutePath());
        getActivity().startActivityForResult(intent, CONVERT);
    }
    private void finish(int token, String signal, String message) {
        getActivity().runOnUiThread(() -> {
            if (token != generation) return;
            generation++;
            cleanup();
            busy = false; emitSignal("busy_changed", false); emitSignal(signal, message);
        });
    }
    @UsedByGodot public void cancel() {
        finish(generation, "failed", "Import cancelled.");
    }
    private void cleanup() {
        if (input != null) { input.delete(); input = null; }
    }
    @Override public void onMainDestroy() { generation++; cleanup(); }
}
