"""Builds a small synthetic Messages database for testing a second account.

    python3 make_fixture.py <output chat.db> <account email>

The schema is copied from this Mac's real chat.db (tables only), so the hub reads the
fixture exactly as it reads the real one. Every name, number and message here is invented.
"""
import os
import sqlite3
import sys
import time

TABLES = ["chat", "message", "handle", "chat_message_join", "chat_handle_join", "attachment", "message_attachment_join"]
APPLE_EPOCH = 978307200


def ns(minutes_ago):
    return int((time.time() - APPLE_EPOCH - minutes_ago * 60) * 1_000_000_000)


def main(output, account):
    if os.path.exists(output):
        os.remove(output)
    real = sqlite3.connect(f"file:{os.path.expanduser('~/Library/Messages/chat.db')}?mode=ro", uri=True)
    fixture = sqlite3.connect(output)
    for table in TABLES:
        (sql,) = real.execute("select sql from sqlite_master where type='table' and name=?", (table,)).fetchone()
        fixture.execute(sql)

    people = [("+15555550101", "iMessage"), ("+15555550102", "iMessage"), ("fixture.friend@example.com", "iMessage")]
    for number, _ in people:
        fixture.execute("insert into handle (id, service) values (?, 'iMessage')", (number,))

    script = [
        (0, ["Is the fixture hub serving the right account?", "Yes, this is Sam's account", "Kyle's messages must never appear here"]),
        (1, ["Lunch tomorrow?", "Sure, noon works"]),
        (2, ["Sent from the second Apple ID"]),
    ]
    for index, (number, service) in enumerate(people):
        handle = index + 1
        cur = fixture.execute(
            "insert into chat (guid, style, state, account_login, chat_identifier, service_name) values (?, 45, 3, ?, ?, ?)",
            (f"any;-;{number}", f"E:{account}", number, service),
        )
        chat = cur.lastrowid
        fixture.execute("insert into chat_handle_join (chat_id, handle_id) values (?, ?)", (chat, handle))
        for n, text in enumerate(script[index][1]):
            mine = n % 2 == 1
            when = ns(60 * (index + 1) - n * 3)
            mcur = fixture.execute(
                "insert into message (guid, text, handle_id, date, is_from_me, is_read, item_type, service) values (?, ?, ?, ?, ?, ?, 0, 'iMessage')",
                (f"fixture-{index}-{n}", text, 0 if mine else handle, when, int(mine), 1 if mine or index > 0 else 0),
            )
            fixture.execute(
                "insert into chat_message_join (chat_id, message_id, message_date) values (?, ?, ?)", (chat, mcur.lastrowid, when)
            )
    fixture.commit()
    print("wrote", output)


if __name__ == "__main__":
    main(sys.argv[1], sys.argv[2])
