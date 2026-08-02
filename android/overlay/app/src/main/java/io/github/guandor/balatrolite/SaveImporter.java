package io.github.guandor.balatrolite;

import java.io.ByteArrayOutputStream;
import java.io.File;
import java.io.FileOutputStream;
import java.io.IOException;
import java.io.InputStream;
import java.util.HashMap;
import java.util.Map;
import java.util.zip.ZipEntry;
import java.util.zip.ZipInputStream;

/** Validates and atomically installs Balatro profile 1 from a small ZIP archive. */
final class SaveImporter {
    private static final String[] SAVE_FILES = {"meta.jkr", "profile.jkr", "save.jkr"};
    private static final int MAX_ZIP_ENTRIES = 256;
    private static final int MAX_FILE_BYTES = 16 * 1024 * 1024;
    private static final int MAX_TOTAL_BYTES = 32 * 1024 * 1024;

    private SaveImporter() {}

    static void importZip(InputStream source, File saveDirectory) throws IOException {
        Map<String, byte[]> files = readSaveFiles(source);
        File profileDirectory = new File(saveDirectory, "1");
        SaveMigrator.ensureDirectory(profileDirectory);
        installAtomically(files, profileDirectory);
    }

    private static Map<String, byte[]> readSaveFiles(InputStream source) throws IOException {
        Map<String, byte[]> files = new HashMap<>();
        String archiveLayout = null;
        int entryCount = 0;
        int totalBytes = 0;

        try (ZipInputStream zip = new ZipInputStream(source)) {
            ZipEntry entry;
            while ((entry = zip.getNextEntry()) != null) {
                if (++entryCount > MAX_ZIP_ENTRIES) {
                    throw new IOException("The save ZIP contains too many entries.");
                }
                if (entry.isDirectory()) {
                    zip.closeEntry();
                    continue;
                }

                SaveEntry saveEntry = identify(entry.getName());
                if (saveEntry == null) {
                    zip.closeEntry();
                    continue;
                }
                if (archiveLayout != null && !archiveLayout.equals(saveEntry.layout)) {
                    throw new IOException(
                        "Keep all three save files together in the ZIP root or in its 1 folder."
                    );
                }
                archiveLayout = saveEntry.layout;
                if (files.containsKey(saveEntry.filename)) {
                    throw new IOException("The save ZIP contains " + saveEntry.filename + " twice.");
                }

                byte[] contents = readLimited(zip, saveEntry.filename);
                if (contents.length == 0) {
                    throw new IOException(saveEntry.filename + " is empty.");
                }
                totalBytes += contents.length;
                if (totalBytes > MAX_TOTAL_BYTES) {
                    throw new IOException("The save ZIP is larger than expected.");
                }
                files.put(saveEntry.filename, contents);
                zip.closeEntry();
            }
        }

        for (String filename : SAVE_FILES) {
            if (!files.containsKey(filename)) {
                throw new IOException("The save ZIP is missing " + filename + ".");
            }
        }
        return files;
    }

    private static SaveEntry identify(String entryName) {
        String path = entryName.replace('\\', '/');
        while (path.startsWith("./")) {
            path = path.substring(2);
        }
        for (String filename : SAVE_FILES) {
            if (path.equals(filename)) {
                return new SaveEntry("root", filename);
            }
            if (path.equals("1/" + filename)) {
                return new SaveEntry("profile", filename);
            }
        }
        return null;
    }

    private static byte[] readLimited(InputStream input, String filename) throws IOException {
        ByteArrayOutputStream output = new ByteArrayOutputStream();
        byte[] buffer = new byte[32 * 1024];
        int count;
        while ((count = input.read(buffer)) >= 0) {
            if (output.size() + count > MAX_FILE_BYTES) {
                throw new IOException(filename + " is larger than expected.");
            }
            output.write(buffer, 0, count);
        }
        return output.toByteArray();
    }

    private static void installAtomically(Map<String, byte[]> files, File profileDirectory)
        throws IOException {
        String transaction = Long.toHexString(System.nanoTime());
        Map<String, File> temporary = new HashMap<>();
        Map<String, File> backups = new HashMap<>();
        Map<String, Boolean> installed = new HashMap<>();

        try {
            for (String filename : SAVE_FILES) {
                File staging = new File(profileDirectory, "." + filename + ".import-" + transaction);
                writeSynced(staging, files.get(filename));
                temporary.put(filename, staging);
            }

            for (String filename : SAVE_FILES) {
                File destination = new File(profileDirectory, filename);
                if (destination.exists()) {
                    File backup = new File(
                        profileDirectory, "." + filename + ".backup-" + transaction
                    );
                    if (!destination.renameTo(backup)) {
                        throw new IOException("Could not prepare to replace " + filename + ".");
                    }
                    backups.put(filename, backup);
                }
            }

            for (String filename : SAVE_FILES) {
                File destination = new File(profileDirectory, filename);
                if (!temporary.get(filename).renameTo(destination)) {
                    throw new IOException("Could not install " + filename + ".");
                }
                installed.put(filename, true);
            }
        } catch (IOException error) {
            for (String filename : SAVE_FILES) {
                if (installed.containsKey(filename)) {
                    new File(profileDirectory, filename).delete();
                }
                File backup = backups.get(filename);
                if (backup != null) {
                    backup.renameTo(new File(profileDirectory, filename));
                }
            }
            throw error;
        } finally {
            for (File staging : temporary.values()) {
                staging.delete();
            }
        }

        for (File backup : backups.values()) {
            backup.delete();
        }
    }

    private static void writeSynced(File destination, byte[] contents) throws IOException {
        try (FileOutputStream output = new FileOutputStream(destination)) {
            output.write(contents);
            output.getFD().sync();
        }
    }

    private static final class SaveEntry {
        final String layout;
        final String filename;

        SaveEntry(String layout, String filename) {
            this.layout = layout;
            this.filename = filename;
        }
    }
}
