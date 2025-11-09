import json
import re


def clean_json_string(llm_text: str) -> str:
    """
    Remove triple quotes, backticks, or extra markdown before parsing JSON.
    """
    # Remove triple single or double quotes
    cleaned = re.sub(r"^('{3}|\"{3})|('{3}|\"{3})$", "", llm_text.strip())

    # Remove markdown code fences ```json ... ``` or ```
    cleaned = re.sub(r"^```(json)?", "", cleaned.strip())
    cleaned = re.sub(r"```$", "", cleaned.strip())

    return cleaned.strip()

def parse_llm_json(llm_text: str):
    cleaned = clean_json_string(llm_text)
    data = json.loads(cleaned)
    return data


if __name__ == '__main__':
    raw_json = """
                ```json
                {
                "order": ["hazard detector"]
                }
                ```
                """
    
    cleaned_json = parse_llm_json(raw_json)
    print(cleaned_json)