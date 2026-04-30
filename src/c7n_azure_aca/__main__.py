"""Entry point for python -m c7n_azure_aca."""

import logging

# Configure logging before any other initialization
logging.basicConfig(
    level=logging.INFO,
    format="%(asctime)s %(name)s %(levelname)s %(message)s",
)

# Initialize c7n-azure provider (registers Azure resource types and container-host modes)
from c7n_azure.entry import initialize_azure  # noqa: E402
from c7n_azure_aca.handler import main  # noqa: E402

initialize_azure()
main()
