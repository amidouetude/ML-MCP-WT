function hex = e5_sha256(file_path)
%E5_SHA256  SHA-256 of a file, lower-case hexadecimal (read only); body of o8_sha256.m with the
%rule of the launch blocks for a file of 0 bytes (SHA-256 of the empty input, without digest).
%
%   hex = e5_sha256(file_path)

if ~isfile(file_path)
    error('e5_sha256:missing', 'File not found: %s', file_path);
end
raw = java.nio.file.Files.readAllBytes(toPath(java.io.File(file_path)));
if isempty(raw)
    hex = 'e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855';
else
    md_engine = java.security.MessageDigest.getInstance('SHA-256');
    hex = lower(reshape(dec2hex(typecast(digest(md_engine, raw), 'uint8'), 2).', 1, []));
end
end
