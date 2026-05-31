import re

filenames = [
    "10_of_Clubs",
    "jack_of_clubs",
    "jack_of_clubs2",
    "A_of_Spades"
]

for base in filenames:
    m = re.match(r"^(.+?)_of_(.+?)(2)?$", base, re.IGNORECASE)
    if not m:
        print(f"FAILED: {base}")
    else:
        print(f"MATCH: {base} -> {m.groups()}")
