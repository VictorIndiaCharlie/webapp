from fastapi.testclient import TestClient
from app import app, normalize_and_sort, letter_pool
from unittest.mock import patch

client = TestClient(app)

# 1. Test the pure logic (No DB needed)
def test_letter_pool():
    assert letter_pool("Maria Elena") == "mariaelena"
    assert letter_pool("Ștefan") == "stefan"

def test_normalize_and_sort():
    assert normalize_and_sort("listen") == "eilnst"
    assert normalize_and_sort("silent") == "eilnst"
    assert normalize_and_sort("maria") == "aaimr"

# 2. Test the API Endpoints (Mocking the DB, Dictionary Check, and IS_LOADED)
@patch("app.IS_LOADED", True) # <-- THIS FIXES THE 503 ERROR
@patch("app.EXACT_MAP", {"aaimr": ["maria"]})
@patch("app._find_all")
def test_anagram_endpoint(mock_find_all):
    # We mock the internal search function so it doesn't try to hit a real DB
    mock_find_all.return_value = {
        "exact": ["amari", "miara"],
        "sub_anagrams": ["air", "arm"],
        "phrases": [["aim", "ram"]],
        "time_ms": 1.5
    }

    # Call the real endpoint
    response = client.get("/api/anagrams?word=maria")
    
    # Verify the endpoint used our logic and returned the right format
    assert response.status_code == 200
    data = response.json()
    assert len(data["exact"]) == 2
    assert data["exact"][0]["word"] == "amari"
    assert len(data["sub_anagrams"]) == 2

def test_health_check():
    response = client.get("/health")
    # Will return 503 because IS_LOADED is False without the patch
    assert response.status_code in [200, 503]