function hex = o8_sha256(file_path)
%O8_SHA256  SHA-256 of a file, lower-case hexadecimal (read only).
%
%   hex = o8_sha256(file_path)

if ~isfile(file_path)
    error('o8_sha256:missing', 'File not found: %s', file_path);
end
md_engine = java.security.MessageDigest.getInstance('SHA-256');
raw = digest(md_engine, java.nio.file.Files.readAllBytes(toPath(java.io.File(file_path))));
hex = lower(reshape(dec2hex(typecast(raw, 'uint8'), 2).', 1, []));
end
