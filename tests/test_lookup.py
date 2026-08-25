from skincaresync.lookup import extract_product_code


def test_extract_product_code_from_plain_barcode():
    assert extract_product_code("1234567890123") == "1234567890123"


def test_extract_product_code_from_qr_url():
    assert extract_product_code("https://example.com/products/1234567890123") == "1234567890123"

