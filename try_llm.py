from mage.config import load_config
from mage.llm_client import LLMClient

llm = LLMClient(load_config())

print("The Generated Code", "-"*20, ">")
print(llm.generate(
    "Write a Verilog module for a 2-input AND gate. Reply with code only.",
    system_prompt="You are an expert RTL design engineer.",
))