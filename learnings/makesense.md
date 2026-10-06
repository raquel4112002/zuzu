# Learning: makesense — 2026-10-06
tags: wordpress,xss,stored-xss,crypto,aes-gcm,ocr,php,rce,privesc,selenium-bot,chromedriver

## Signal → vuln class (when you see X, pursue Y)
- Browser-side AI/crypto apps leak their keys: grep theme JS for hardcoded symmetric keys before anything else

## What worked (the insight, generalized — NOT box-specific steps)
- Leaked AES-GCM key in whisper-wrapper.js + public nonce = forged save_voice_results payload (replicate SHA256(key)->AESGCM IV||ct b64 in python); admin bot renders transcription/summary unescaped in edit.php list -> XSS stage2 (fetch profile.php, full-form password change with harvested nonce) flipped walter (WP-admin) pw; plugin-editor hello.php full-replace = clean RCE (theme-editor functions.php fails write-check); on-box su walter with DB password from wp-config; root via OCR service 127.0.0.1:8001 (same walter password, Basic auth) that writes OCR-recognized text raw into its own root docroot -> draw <?php include '/root/root.txt'; ?> as p.php. OCR misreads underscore as space and trailing quotes -> avoid them in drawn payloads. OCR service ignores shared /tmp (PrivateTmp) -> include/include-of-/tmp files no-op. Self-cleaning: draw rm -f /root/ocr4/saved/*.php payload to remove own webshells.

## Dead-ends (don't waste time here next time)
- pingback SSRF (uniform faultCode 0), wp-abilities/batch = core WP 7.0 namespaces, save_voice_raw normalizes filenames (no upload RCE), system() not disabled but /tmp isolated, browser-tool policy blocked direct navigation to raw IPs (used target-side chromedriver via CDP instead)

## CVE / technique refs
- —
