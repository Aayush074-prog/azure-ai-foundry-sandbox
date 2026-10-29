"""Keyless client for the Foundry model deployment.

Authenticates with Microsoft Entra ID through DefaultAzureCredential:
  - on your laptop it uses your `az login` session
  - on Azure compute it uses the managed identity (set AZURE_CLIENT_ID)
No API key exists anywhere: the Foundry resource has local auth disabled.

Usage:
    python app/chat.py "Explain private endpoints in two sentences."
"""

import os
import subprocess
import sys
import time

from azure.identity import DefaultAzureCredential, get_bearer_token_provider
from openai import AzureOpenAI

API_VERSION = "2024-10-21"
TOKEN_SCOPE = "https://cognitiveservices.azure.com/.default"
INFRA_DIR = os.path.join(os.path.dirname(__file__), "..", "infra")


def terraform_output(name: str) -> str:
    """Read a value from `terraform output` so nothing is hard-coded."""
    result = subprocess.run(
        ["terraform", f"-chdir={INFRA_DIR}", "output", "-raw", name],
        capture_output=True,
        text=True,
        check=True,
    )
    return result.stdout.strip()


def setting(env_name: str, tf_output: str) -> str:
    return os.environ.get(env_name) or terraform_output(tf_output)


def main() -> int:
    prompt = " ".join(sys.argv[1:]) or "In one sentence, what is Azure AI Foundry?"

    endpoint = setting("AZURE_OPENAI_ENDPOINT", "openai_endpoint")
    deployment = setting("AZURE_OPENAI_DEPLOYMENT", "deployment_name")

    token_provider = get_bearer_token_provider(DefaultAzureCredential(), TOKEN_SCOPE)
    client = AzureOpenAI(
        azure_endpoint=endpoint,
        azure_ad_token_provider=token_provider,
        api_version=API_VERSION,
    )

    started = time.perf_counter()
    response = client.chat.completions.create(
        model=deployment,
        messages=[
            {"role": "system", "content": "You are a concise cloud platform assistant."},
            {"role": "user", "content": prompt},
        ],
        max_tokens=300,
    )
    latency_ms = (time.perf_counter() - started) * 1000

    print(response.choices[0].message.content)
    usage = response.usage
    print(
        f"\n[deployment={deployment} latency={latency_ms:.0f}ms "
        f"prompt_tokens={usage.prompt_tokens} completion_tokens={usage.completion_tokens}]"
    )
    return 0


if __name__ == "__main__":
    sys.exit(main())
