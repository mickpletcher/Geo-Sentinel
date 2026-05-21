# Sources

The policy builder accepts source files placed in each data category folder.

## Expected Source Types

1. OFAC sanctions datasets
2. EU sanctions datasets
3. UK sanctions datasets
4. UN sanctions datasets
5. FATF high risk jurisdiction lists
6. TOR exit node datasets
7. Spamhaus network intelligence datasets
8. ipdeny country CIDR datasets
9. MaxMind geolocation and network datasets
10. AbuseIPDB reputation and abuse datasets
11. Custom business rule datasets maintained internally

## Supported Input File Formats

1. Plain text files such as countries.txt and cidrs.txt
2. CSV files with country or network fields
3. JSON files with countries and cidrs keys

## Data Handling Notes

1. Country values are normalized to ISO 3166 alpha 2 codes.
2. CIDR values are normalized to canonical network notation.
3. Duplicate entries are removed during build.
4. Validation failures stop output generation.
