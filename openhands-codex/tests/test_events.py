from codex import ErrorItem, ItemCompleted


def test_error_item_json(snapshot):
    item = ErrorItem(id="test_id", message="test message")
    json_str = item.model_dump_json()
    snapshot.assert_match(json_str)


def test_item_completed_json(snapshot):
    item = ErrorItem(id="error1", message="An error occurred")
    event = ItemCompleted(item=item)
    json_str = event.model_dump_json()
    snapshot.assert_match(json_str)
