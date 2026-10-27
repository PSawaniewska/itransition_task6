# Builds seed.sql with the lookup lists.
# The word lists (names, streets, cities) come from the open-source Faker library.
# Only the lists are taken from it, all data generation happens in SQL.

from faker.providers.address.de_DE import Provider as AddressDE
from faker.providers.address.en_US import Provider as AddressUS
from faker.providers.internet import Provider as InternetBase
from faker.providers.internet.de_DE import Provider as InternetDE
from faker.providers.person.de_DE import Provider as PersonDE
from faker.providers.person.en_US import Provider as PersonUS

LOCALES = [
    # code, name, mean height male / female, standard deviation (cm)
    ("en_US", "English (USA)", 175.4, 161.7, 7.0),
    ("de_DE", "German (Germany)", 179.9, 166.1, 7.0),
]

EMAIL_FORMATS = {"{first}.{last}": 3, "{f}{last}": 2, "{first}{last}##": 1, "{last}.{first}": 1, "{first}_{last}": 1}

WORDS = {
    "en_US": {
        "first_name_male": PersonUS.first_names_male,
        "first_name_female": PersonUS.first_names_female,
        "last_name": PersonUS.last_names,
        "title_male": {"Mr.": 7, "Dr.": 3},
        "title_female": {"Mrs.": 5, "Ms.": 2, "Miss": 1, "Dr.": 3},
        "name_format": {"{first} {last}": 12, "{title} {first} {last}": 3, "{first} {m}. {last}": 3, "{first} {middle} {last}": 2},
        "street_suffix": AddressUS.street_suffixes,
        "street_format": {"{last} {suffix}": 1, "{first} {suffix}": 1},
        "city_prefix": AddressUS.city_prefixes,
        "city_suffix": sorted(set(AddressUS.city_suffixes)),
        "city_format": {"{city_prefix} {first}{city_suffix}": 1, "{city_prefix} {first}": 1,
                        "{first}{city_suffix}": 1, "{last}{city_suffix}": 1},
        "region": AddressUS.states_abbr,
        "postcode_format": {"#####": 3, "#####-####": 1},
        "building_format": {"%##": 2, "%###": 3, "%####": 2},
        "secondary_format": {"Apt. %##": 2, "Suite %##": 1},
        "address_format": {"{number} {street}, {city}, {region} {zip}": 3,
                           "{number} {street} {secondary}, {city}, {region} {zip}": 1},
        "phone_format": {"(%##) %##-####": 3, "%##-%##-####": 3, "%##.%##.####": 2,
                         "+1 %##-%##-####": 2, "%##-%##-#### x###": 1},
        "email_format": EMAIL_FORMATS,
        "email_domain": InternetBase.free_email_domains,
        "eye_color": {"brown": 45, "blue": 27, "hazel": 18, "green": 9, "gray": 1},
    },
    "de_DE": {
        "first_name_male": PersonDE.first_names_male,
        "first_name_female": PersonDE.first_names_female,
        "last_name": PersonDE.last_names,
        "title_male": {"Herr": 6, "Dr.": 2, "Prof.": 1, "Dipl.-Ing.": 1},
        "title_female": {"Frau": 6, "Dr.": 2, "Prof.": 1, "Dipl.-Ing.": 1},
        "name_format": {"{first} {last}": 12, "{title} {first} {last}": 4, "{first} {middle} {last}": 4},
        "street_suffix_short": AddressDE.street_suffixes_short,
        "street_suffix_long": AddressDE.street_suffixes_long,
        "street_format": {"{last}{suffix_short}": 4, "{first}-{last}-{suffix_long}": 1},
        "city": AddressDE.cities,
        "city_format": {"{city}": 1},
        "region": AddressDE.states,
        "postcode_format": {"#####": 1},
        "building_format": {"%": 3, "%#": 4, "%#a": 1, "%##": 1},
        "address_format": {"{street} {number}, {zip} {city}": 3, "{street} {number}, D-{zip} {city}": 1},
        "phone_format": {"0%## #######": 3, "0%### ######": 3, "(0%###) ######": 2,
                         "+49 %## #######": 2, "+49 (0) %### ######": 1},
        "email_format": EMAIL_FORMATS,
        "email_domain": InternetDE.free_email_domains,
        "eye_color": {"blau": 40, "braun": 30, "grün": 15, "grau": 10, "hellbraun": 5},
    },
}


def sql_text(value):
    return "'" + str(value).replace("'", "''") + "'"


def main():
    lines = ["BEGIN;", "TRUNCATE words, locales;"]
    for code, name, male, female, sd in LOCALES:
        lines.append(f"INSERT INTO locales VALUES ({sql_text(code)}, {sql_text(name)}, {male}, {female}, {sd});")

    for locale, categories in WORDS.items():
        for category, values in categories.items():
            # plain lists get weight 1, dicts carry their own weights
            weighted = values.items() if isinstance(values, dict) else ((v, 1) for v in values)
            rows = [f"({sql_text(locale)}, {sql_text(category)}, {i}, {sql_text(v)}, {w})"
                    for i, (v, w) in enumerate(weighted)]
            lines.append("INSERT INTO words (locale, category, idx, value, weight) VALUES\n" + ",\n".join(rows) + ";")

    lines += [
        "UPDATE words w SET cum_weight = s.running FROM ("
        "SELECT locale, category, idx, sum(weight) OVER (PARTITION BY locale, category ORDER BY idx) AS running "
        "FROM words) s WHERE (w.locale, w.category, w.idx) = (s.locale, s.category, s.idx);",
        "REFRESH MATERIALIZED VIEW word_counts;",
        "ANALYZE words, word_counts;",
        "COMMIT;",
    ]
    with open("seed.sql", "w", encoding="utf-8") as f:
        f.write("\n".join(lines) + "\n")


if __name__ == "__main__":
    main()
