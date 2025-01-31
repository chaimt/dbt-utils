{%- macro union_relations_ex(relations, column_override=none, include=[], exclude=[], source_column_name='_dbt_source_relation', rename_columns=none) -%}

{%- if exclude and include -%}
        {{ exceptions.raise_compiler_error("Both an exclude and include list were provided to the `union` macro. Only one is allowed") }}
    {%- endif -%}

    {#-- Prevent querying of db in parsing mode. This works because this macro does not create any new refs. -#}
    {%- if not execute %}
        {{ return('') }}
    {% endif -%}

    {%- set column_override = column_override if column_override is not none else {} -%}
    {%- set rename_columns = rename_columns if rename_columns is not none else {} -%}

    {%- set relation_columns = {} -%}
    {%- set column_superset = {} -%}

    {%- for relation in relations -%}

        {%- do relation_columns.update({relation: {}}) -%}

        {%- do dbt_utils._is_relation(relation, 'union_relations') -%}
        {%- do dbt_utils._is_ephemeral(relation, 'union_relations') -%}
        {%- set cols = adapter.get_columns_in_relation(relation) -%}
        {%- for col in cols -%}

        {#- If an exclude list was provided and the column is in the list, do nothing -#}
        {%- if exclude and col.column in exclude -%}

        {#- If an include list was provided and the column is not in the list, do nothing -#}
        {%- elif include and col.column not in include -%}

        {#- Otherwise add the column to the column superset -#}
        {%- else -%}

            {#- update the list of columns in this relation -#}
            {%- set rename_col = rename_columns[col.column]|default(col.column) -%}
            
            {%- do relation_columns[relation].update({rename_col: col}) -%}

            {%- if rename_col in column_superset -%}

                {%- set stored = column_superset[rename_col] -%}
                {%- if col.is_string() and stored.is_string() and col.string_size() > stored.string_size() -%}

                    {%- do column_superset.update({rename_col: col}) -%}

                {%- endif %}

            {%- else -%}

                {%- do column_superset.update({rename_col: col}) -%}

            {%- endif -%}

        {%- endif -%}

        {%- endfor -%}
    {%- endfor -%}

    {%- set ordered_column_names = column_superset.keys() -%}

    {%- for relation in relations %}

        (
            select

                cast({{ dbt_utils.string_literal(relation) }} as {{ dbt_utils.type_string() }}) as {{ source_column_name }},
                {% for col_name in ordered_column_names -%}
                    {%- set col = column_superset[col_name] %}
                    {%- set col_type = column_override.get(col.column, col.data_type) %}
                    {%- set col_name_quote = adapter.quote(col_name) %}
                    {%- set orig_col_name = adapter.quote(relation_columns[relation][col_name].column) if col_name in relation_columns[relation] else 'null' %}
                    cast({{ orig_col_name }} as {{ col_type }}) as {{ col_name_quote }} {% if not loop.last %},{% endif -%}

                {%- endfor %}

            from {{ relation }}
        )

        {% if not loop.last -%}
            union all
        {% endif -%}

    {%- endfor -%}

{%- endmacro -%}
