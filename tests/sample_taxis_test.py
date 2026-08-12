from dab_demo import taxis


def test_find_all_taxis():
    results = taxis.find_all_taxis()
    assert results.count() > 5
