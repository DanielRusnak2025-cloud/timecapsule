<?php
// File storage for capsule attachments — S3 backend.
//
// This is the only file that reads or writes uploaded files. They are now kept in an
// Amazon S3 bucket under the "uploads/" prefix instead of the local disk. The rest of
// the app only uses storage_save(), storage_delete() and storage_stream().
//
// Credentials: none are configured here. The SDK automatically picks up the temporary
// credentials of the EC2 instance role (timecapsule-dev-app-role) via the instance
// metadata service — exactly like the AWS CLI did. No access keys in .env.

use Aws\S3\S3Client;

function s3_client(): S3Client
{
    static $client = null;
    if ($client === null) {
        $client = new S3Client([
            'region'  => config('AWS_REGION', 'eu-central-1'),
            'version' => 'latest',
        ]);
    }
    return $client;
}

function s3_bucket(): string
{
    $bucket = config('S3_BUCKET', '');
    if ($bucket === '') {
        throw new RuntimeException('S3_BUCKET is not configured.');
    }
    return $bucket;
}

function s3_key(string $storedName): string
{
    return 'uploads/' . basename($storedName);
}

// Save an uploaded file and return its random stored name, e.g. "3f9a...e1.png".
function storage_save(array $uploadedFile, string $extension): string
{
    $storedName = bin2hex(random_bytes(16)) . '.' . $extension;

    $mime = mime_content_type($uploadedFile['tmp_name']) ?: 'application/octet-stream';

    s3_client()->putObject([
        'Bucket'      => s3_bucket(),
        'Key'         => s3_key($storedName),
        'SourceFile'  => $uploadedFile['tmp_name'],
        'ContentType' => $mime,
    ]);

    return $storedName;
}

function storage_delete(?string $storedName): void
{
    if ($storedName === null || $storedName === '') {
        return;
    }

    s3_client()->deleteObject([
        'Bucket' => s3_bucket(),
        'Key'    => s3_key($storedName),
    ]);
}

// Redirect (302) the browser to a 5-minute presigned URL. The app checks the user's
// permission on the capsule BEFORE calling this; S3 knows nothing about app users.
function storage_stream(string $storedName, string $mime, string $downloadName, string $disposition): void
{
    $asciiName = preg_replace('/[^A-Za-z0-9._ -]/', '_', $downloadName);

    $contentDisposition = sprintf(
        '%s; filename="%s"; filename*=UTF-8\'\'%s',
        $disposition,
        $asciiName,
        rawurlencode($downloadName)
    );

    $command = s3_client()->getCommand('GetObject', [
        'Bucket'                     => s3_bucket(),
        'Key'                        => s3_key($storedName),
        'ResponseContentType'        => $mime,
        'ResponseContentDisposition' => $contentDisposition,
    ]);

    $request = s3_client()->createPresignedRequest($command, '+5 minutes');
    $url = (string) $request->getUri();

    header('Location: ' . $url, true, 302);
    exit;
}
