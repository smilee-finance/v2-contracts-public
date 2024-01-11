import re


def outputToSol():
    data = ""
    with open('example.txt', 'r') as file:
        data = file.read()
        data = data.replace("*wait* ", "")
        data = re.sub(r"([a-zA-z]+\(.*\)) (Time delay: .*\n)", r"\1\n    \2", data)
        data = re.sub(r"Time delay: (\d+) .*\n", r"vm.warp(\1)\n", data)
        data = re.sub(r"\)", r");", data)
        data = re.sub(r"0x([a-fA-F0-9]+),", r"address(0x\1),", data)
    return data


def fillFile(content, folder="ig"):
    data = ""

    with open(f"{folder}/CryticToFoundry.t.sol", 'r') as file:
        data = file.read()
        data = re.sub(r"(function test\(\) public \{)(.*\n)+(  \})", r"\1\n" + content + r"  }", data)

    with open(f'{folder}/CryticToFoundry.t.sol', 'w') as file:
        file.write(data)


content = outputToSol()
fillFile(content, "ig")
