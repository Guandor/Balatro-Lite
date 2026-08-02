package io.github.guandor.balatrolite;

import java.io.ByteArrayInputStream;
import java.io.ByteArrayOutputStream;
import java.io.File;
import java.io.IOException;
import java.nio.charset.StandardCharsets;
import java.nio.file.Files;
import java.util.LinkedHashMap;
import java.util.Map;
import java.util.zip.ZipEntry;
import java.util.zip.ZipOutputStream;

/** Host-JVM checks for both supported save ZIP layouts and safe replacement. */
public final class SaveImporterSmokeTest {
    private SaveImporterSmokeTest() {}

    public static void main(String[] args) throws Exception {
        File root = Files.createTempDirectory("balatro-save-import-").toFile();
        try {
            SaveImporter.importZip(new ByteArrayInputStream(saveZip("", "root")), root);
            requireProfile(root, "root");

            SaveImporter.importZip(new ByteArrayInputStream(saveZip("1/", "folder")), root);
            requireProfile(root, "folder");

            Map<String, String> incomplete = new LinkedHashMap<>();
            incomplete.put("meta.jkr", "incomplete");
            incomplete.put("profile.jkr", "incomplete");
            expectFailure(zip(incomplete), root, "missing save.jkr");
            requireProfile(root, "folder");

            Map<String, String> mixed = new LinkedHashMap<>();
            mixed.put("meta.jkr", "mixed");
            mixed.put("1/profile.jkr", "mixed");
            mixed.put("save.jkr", "mixed");
            expectFailure(zip(mixed), root, "mixed layouts");
            requireProfile(root, "folder");

            Map<String, String> traversal = new LinkedHashMap<>();
            traversal.put("../meta.jkr", "unsafe");
            traversal.put("../profile.jkr", "unsafe");
            traversal.put("../save.jkr", "unsafe");
            expectFailure(zip(traversal), root, "path traversal");
            requireProfile(root, "folder");

            System.out.println("Both save ZIP layouts and validation verified.");
        } finally {
            deleteTree(root);
        }
    }

    private static byte[] saveZip(String prefix, String value) throws IOException {
        Map<String, String> files = new LinkedHashMap<>();
        files.put(prefix + "meta.jkr", value);
        files.put(prefix + "profile.jkr", value);
        files.put(prefix + "save.jkr", value);
        return zip(files);
    }

    private static byte[] zip(Map<String, String> files) throws IOException {
        ByteArrayOutputStream bytes = new ByteArrayOutputStream();
        try (ZipOutputStream zip = new ZipOutputStream(bytes)) {
            for (Map.Entry<String, String> file : files.entrySet()) {
                zip.putNextEntry(new ZipEntry(file.getKey()));
                zip.write(file.getValue().getBytes(StandardCharsets.UTF_8));
                zip.closeEntry();
            }
        }
        return bytes.toByteArray();
    }

    private static void expectFailure(byte[] archive, File root, String scenario)
        throws Exception {
        try {
            SaveImporter.importZip(new ByteArrayInputStream(archive), root);
            throw new IllegalStateException("Invalid ZIP accepted: " + scenario);
        } catch (IOException expected) {
            // Expected validation failure.
        }
    }

    private static void requireProfile(File root, String value) throws Exception {
        for (String filename : new String[] {"meta.jkr", "profile.jkr", "save.jkr"}) {
            File file = new File(root, "1/" + filename);
            require(file.isFile(), filename + " was not imported into profile 1");
            require(Files.readString(file.toPath()).equals(value),
                filename + " has unexpected contents");
        }
    }

    private static void deleteTree(File file) throws Exception {
        if (file.isDirectory()) {
            File[] children = file.listFiles();
            if (children != null) {
                for (File child : children) {
                    deleteTree(child);
                }
            }
        }
        Files.deleteIfExists(file.toPath());
    }

    private static void require(boolean condition, String message) {
        if (!condition) {
            throw new IllegalStateException(message);
        }
    }
}
