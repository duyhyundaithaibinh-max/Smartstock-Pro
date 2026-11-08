from scripts.ingest_curriculum import tokens


def test_curriculum_tokenizer_keeps_vietnamese_words_and_ignores_punctuation():
    result = tokens("Sóng Elliott, Fibonacci 61,8% và quản trị rủi ro!")
    assert result["sóng"] == 1
    assert result["elliott"] == 1
    assert result["fibonacci"] == 1
    assert result["quản"] == 1
    assert result["trị"] == 1
    assert result["rủi"] == 1
    assert result["ro"] == 1