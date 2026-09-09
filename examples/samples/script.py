# examples/samples/script.py
def greet(name):
    return "hello " + name


def shout(name):
    return greet(name).upper()


def whisper(name):
    return greet(name).lower()
