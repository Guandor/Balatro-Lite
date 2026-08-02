package io.github.guandor.balatrolite;

import java.io.File;
import java.io.FileInputStream;
import java.io.FileOutputStream;
import java.io.IOException;

/** Copies saves from LÖVE's legacy internal directory without replacing newer files. */
final class SaveMigrator {
    private SaveMigrator() {}

    static void copyMissing(File source, File destination) throws IOException {
        ensureDirectory(destination);
        if (!source.isDirectory()) {
            return;
        }

        File[] entries = source.listFiles();
        if (entries == null) {
            throw new IOException("Could not read the existing save directory.");
        }
        for (File entry : entries) {
            File target = new File(destination, entry.getName());
            if (entry.isDirectory()) {
                copyMissing(entry, target);
            } else if (entry.isFile() && !target.exists()) {
                copyFile(entry, target);
            }
        }
    }

    static void ensureDirectory(File directory) throws IOException {
        if (directory.isDirectory()) {
            return;
        }
        if (directory.exists() || !directory.mkdirs()) {
            throw new IOException("Could not create the external save directory.");
        }
    }

    private static void copyFile(File source, File destination) throws IOException {
        File temporary = new File(destination.getParentFile(), destination.getName() + ".migrating");
        if (temporary.exists() && !temporary.delete()) {
            throw new IOException("Could not replace an incomplete save migration.");
        }

        try (FileInputStream input = new FileInputStream(source);
             FileOutputStream output = new FileOutputStream(temporary)) {
            byte[] buffer = new byte[64 * 1024];
            int count;
            while ((count = input.read(buffer)) >= 0) {
                output.write(buffer, 0, count);
            }
            output.getFD().sync();
        } catch (IOException error) {
            temporary.delete();
            throw error;
        }

        if (!temporary.renameTo(destination)) {
            temporary.delete();
            throw new IOException("Could not finish migrating " + source.getName() + ".");
        }
    }
}
