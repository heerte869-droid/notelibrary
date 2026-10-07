Source: https://github.com/BerriAI/litellm
Revision: d80f8c28ca7e2fba4257b4b97457d3b313ff0d6a

The image protocol mapping is ported to ImageGenerationProtocol in CompatibleAIClient.swift. We retain the caller-selected host/region and never retry a generation to detect protocol. The Python reference is not executed or bundled.
