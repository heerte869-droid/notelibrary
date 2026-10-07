# Document import fixtures

The generated samples are synthetic test documents. ../make_document_fixtures.py recreates the lesson.*, blank.pptx, scanned.pdf, locked.pdf, page.html, text/CSV, unsafe.docx and entity.docx samples using python-docx, python-pptx, openpyxl, ReportLab and Pillow. Malformed and password-protected files exercise rejection paths. The generated encryption password is test data, not an account credential.

Three unchanged legacy PowerPoint samples come from [Apache POI](https://poi.apache.org/) under [Apache License 2.0](APACHE-2.0.txt). The upstream [NOTICE](NOTICE) is retained unchanged.

| Local file | Upstream file |
| --- | --- |
| legacy-basic.ppt | test-data/slideshow/basic_test_ppt_file.ppt |
| legacy-reordered.ppt | test-data/slideshow/incorrect_slide_order.ppt |
| legacy-encrypted.ppt | test-data/slideshow/Password_Protected-hello.ppt |

On 2026-10-07 all three local binaries were compared byte for byte with upstream revision ae62bb5116b9aee19ebd5834e3a82066132c9f7f. [UPSTREAM.json](UPSTREAM.json) contains immutable links, sizes, SHA-256 hashes and the NOTICE source hash. This is a verification revision, not a claim about the original retrieval revision.

These resources belong to the XCTest bundle, not the application target. Do not replace them with personal documents or production exports.
