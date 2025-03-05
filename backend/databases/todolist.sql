CREATE EXTENSION IF NOT EXISTS "uuid-ossp";

-- Пользователи
CREATE TABLE users (
    user_id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    username VARCHAR(50) UNIQUE NOT NULL,
    hashed_password VARCHAR(200) NOT NULL,
    phone VARCHAR(20),
    about VARCHAR(300)
);

--ENUM--
CREATE TYPE permission_type AS ENUM (
    'create_task', 'edit_task', 'delete_task', 'assign_task', 'view_all_tasks',
    'create_list', 'edit_list', 'delete_list', 'create_tag', 'edit_tag', 'delete_tag',
    'add_member', 'remove_member', 'assign_role', 'edit_group', 'view_private_lists',
    'manage_permissions'
);


-- Группы--
CREATE TABLE groups (
    group_id SERIAL PRIMARY KEY,
    name TEXT NOT NULL,
    description VARCHAR(300),
	is_personal BOOLEAN NOT NULL,
	owner_id UUID NOT NULL REFERENCES users(user_id) ON DELETE CASCADE,
	UNIQUE (owner_id, is_personal) -- Только одна личная группа на пользователя

);


-- Роли в группах
CREATE TABLE group_roles (
    role_id SERIAL PRIMARY KEY,
    group_id INTEGER REFERENCES groups(group_id) ON DELETE CASCADE,
    role_name VARCHAR(50) NOT NULL,
	UNIQUE (group_id, role_name)
);


-- Участники групп (многие-ко-многим)
CREATE TABLE group_members (
    group_id INTEGER REFERENCES groups(group_id) ON DELETE CASCADE,
    user_id UUID REFERENCES users(user_id) ON DELETE CASCADE,
	role_id INTEGER NOT NULL REFERENCES group_roles(role_id) ON DELETE CASCADE,
    PRIMARY KEY (group_id, user_id)
);


-- Права ролей (многие-ко-многим)
CREATE TABLE role_permissions (
    role_id INTEGER REFERENCES group_roles(role_id),
	permission permission_type NOT NULL,
    PRIMARY KEY (role_id, permission)
);


-- Списки задач
CREATE TABLE lists (
    list_id SERIAL PRIMARY KEY,
    name VARCHAR(100) NOT NULL,
    group_id INTEGER NOT NULL REFERENCES groups(group_id) ON DELETE CASCADE,
    is_private BOOLEAN DEFAULT TRUE
);



-- Теги
CREATE TABLE tags (
    tag_id SERIAL PRIMARY KEY,
    group_id INTEGER NOT NULL REFERENCES groups(group_id) ON DELETE CASCADE,
    tag_name VARCHAR(50) NOT NULL
);


-- Задачи
CREATE TABLE tasks (
    task_id SERIAL PRIMARY KEY,
    title VARCHAR(100) NOT NULL,
    description TEXT,
    due_date TIMESTAMPTZ,
    completed BOOLEAN DEFAULT FALSE,
    list_id INTEGER REFERENCES lists(list_id) ON DELETE CASCADE,
    tag_id INTEGER REFERENCES tags(tag_id) ON DELETE CASCADE,
    creator_id UUID REFERENCES users(user_id) ON DELETE RESTRICT,
    updater_id UUID REFERENCES users(user_id) ON DELETE SET NULL,
	created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
	CHECK (list_id IS NOT NULL OR tag_id IS NOT NULL)
);

--назначение задач пользователю
CREATE TABLE task_assignees (
    task_id INTEGER REFERENCES tasks(task_id),
    user_id UUID REFERENCES users(user_id) ON DELETE CASCADE,
	assigned_by UUID REFERENCES users(user_id) ON DELETE SET NULL,
	assigned_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    PRIMARY KEY (task_id, user_id)
);


CREATE INDEX idx_group_members_group_user ON group_members(group_id, user_id);
CREATE INDEX idx_role_permissions ON role_permissions(role_id, permission);
CREATE INDEX idx_group_members_role ON group_members(role_id);
CREATE INDEX idx_lists_group ON lists(group_id);
CREATE INDEX idx_task_assignees_user ON task_assignees(user_id);
CREATE INDEX idx_tasks_creator ON tasks(creator_id);
CREATE INDEX idx_tasks_updater ON tasks(updater_id);
CREATE INDEX idx_tasks_completed ON tasks(completed);
CREATE INDEX idx_tasks_due_date ON tasks(due_date);
CREATE INDEX idx_tasks_list ON tasks(list_id);
CREATE INDEX idx_tasks_tag ON tasks(tag_id);
CREATE INDEX idx_tags_group ON tags(group_id);
CREATE INDEX idx_groups_owner ON groups(owner_id);

ALTER TABLE groups
ADD CONSTRAINT personal_group_owner_check 
CHECK (
    is_personal = FALSE 
    OR (
        is_personal = TRUE 
        AND name = 'Personal' 
        AND description = 'Personal group'
    )
);

/* 1. Оптимизация производительности */

Добавление NOT VALID для FK на больших таблицах (пример для tasks)
ALTER TABLE tasks 
ADD CONSTRAINT tasks_list_id_fkey 
FOREIGN KEY (list_id) 
REFERENCES lists(list_id) 
ON DELETE CASCADE 
NOT VALID;

-- Валидация ограничения отдельно (выполнить в период низкой нагрузки)
ALTER TABLE tasks VALIDATE CONSTRAINT tasks_list_id_fkey;


--ФУНКЦИИ--
--вспомогательная функция
CREATE OR REPLACE FUNCTION validate_group_consistency(
    list_id INTEGER, 
    tag_id INTEGER
) RETURNS VOID AS $$
DECLARE
    list_group INTEGER;
    tag_group INTEGER;
BEGIN
	SELECT group_id INTO list_group FROM lists WHERE list_id = validate_group_consistency.list_id;
	SELECT group_id INTO tag_group FROM tags WHERE tag_id = validate_group_consistency.tag_id;
    IF list_group <> tag_group THEN
        RAISE EXCEPTION 
            'Group conflict: list_group=%, tag_group=%', 
            list_group, 
            tag_group;
    END IF;
END;
$$ LANGUAGE plpgsql;


-- Новая функция проверки существования пользователя
CREATE OR REPLACE FUNCTION validate_user_exists(user_id UUID)
RETURNS VOID AS $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 
        FROM users 
        WHERE user_id = validate_user_exists.user_id
    ) THEN
        RAISE EXCEPTION 'User % does not exist', user_id;
    END IF;
END;
$$ LANGUAGE plpgsql;


--функция добавления нового пользователя--
CREATE OR REPLACE FUNCTION create_personal_group()
RETURNS TRIGGER AS $$
DECLARE
    new_group_id INTEGER;
    owner_role_id INTEGER;
BEGIN
    -- 1. Создать группу
    INSERT INTO groups (name, description, is_personal, owner_id)
    VALUES (
        'Personal', 
        'Personal group', 
        TRUE, 
        NEW.user_id
    )
    RETURNING group_id INTO new_group_id;  -- Исправлено: RETURNING здесь

    -- 2. Создать роль "Владелец"
    INSERT INTO group_roles (group_id, role_name)
    VALUES (new_group_id, 'Owner')
    RETURNING role_id INTO owner_role_id;

    -- 3. Назначить все права роли "Владелец"
    INSERT INTO role_permissions (role_id, permission)
    SELECT owner_role_id, unnest(enum_range(NULL::permission_type));

    -- 4. Добавить пользователя в группу
    INSERT INTO group_members (group_id, user_id, role_id)
    VALUES (new_group_id, NEW.user_id, owner_role_id);

    RETURN NEW;
END;
$$ LANGUAGE plpgsql;


CREATE OR REPLACE FUNCTION check_user_context()
RETURNS VOID AS $$
BEGIN
    IF current_setting('app.user_id', true) IS NULL THEN
        RAISE EXCEPTION 'User context must be set using SET LOCAL app.user_id = <user_id>';
    END IF;
END;
$$ LANGUAGE plpgsql;


--Функция проверки прав на задачу
CREATE OR REPLACE FUNCTION check_task_permission()
RETURNS TRIGGER AS $$

DECLARE
    target_group_id INTEGER;
    current_user_id UUID;
BEGIN
    PERFORM check_user_context();
    IF NEW.list_id IS NOT NULL AND NEW.tag_id IS NOT NULL THEN
        PERFORM validate_group_consistency(NEW.list_id, NEW.tag_id);
    END IF;
    -- Новый запрос с явным JOIN
    SELECT COALESCE(l.group_id, t.group_id) INTO target_group_id
    FROM tasks AS tk
    LEFT JOIN lists l ON tk.list_id = l.list_id
    LEFT JOIN tags t ON tk.tag_id = t.tag_id
    WHERE tk.task_id = OLD.task_id;
	IF target_group_id IS NULL THEN
        RAISE EXCEPTION 'Task % is orphaned (no linked list/tag)', OLD.task_id;
    END IF;
    -- Получаем текущего пользователя
    current_user_id := current_setting('app.user_id')::UUID;

    -- Проверка прав
    IF NOT EXISTS (
        SELECT 1
        FROM group_members AS gm
        JOIN role_permissions AS rp ON gm.role_id = rp.role_id
        WHERE gm.group_id = target_group_id
          AND gm.user_id = current_user_id
          AND rp.permission = CASE 
              WHEN TG_OP = 'DELETE' THEN 'delete_task'
              ELSE 'edit_task'
          END
    ) THEN
        RAISE EXCEPTION 'User % has no permission to % task %',
            current_user_id,
            TG_OP,
            OLD.task_id;
    END IF;

    RETURN OLD;
END;
$$ LANGUAGE plpgsql;

--функция смена владельца
-- Обновленная функция transfer_group_ownership (безопасное удаление)
-- Оптимизированная функция transfer_group_ownership
CREATE OR REPLACE FUNCTION transfer_group_ownership()
RETURNS TRIGGER AS $$
DECLARE
    new_owner_id UUID;
BEGIN
    -- Используем CTE для пакетной обработки
    WITH affected_groups AS (
        SELECT group_id 
        FROM groups 
        WHERE owner_id = OLD.user_id 
          AND is_personal = FALSE
    ),
    new_owners AS (
        SELECT DISTINCT ON (gm.group_id)
            gm.group_id,
            COALESCE(
                MAX(gm.user_id) FILTER (WHERE gr.role_name = 'Admin'),
                MAX(gm.user_id)
            ) AS new_owner_id
        FROM group_members gm
        JOIN group_roles gr ON gm.role_id = gr.role_id
        JOIN affected_groups ag ON gm.group_id = ag.group_id
        WHERE gm.user_id <> OLD.user_id
        GROUP BY gm.group_id
    )
    UPDATE groups g
    SET owner_id = no.new_owner_id
    FROM new_owners no
    WHERE g.group_id = no.group_id
      AND no.new_owner_id IS NOT NULL;

    -- Проверка оставшихся групп
    IF EXISTS (
        SELECT 1 
        FROM groups 
        WHERE owner_id = OLD.user_id 
          AND is_personal = FALSE
    ) THEN
        RAISE EXCEPTION 'Не удалось передать ownership для некоторых групп';
    END IF;

    RETURN OLD;
END;
$$ LANGUAGE plpgsql;

--функция автообновления поля update_at--
CREATE OR REPLACE FUNCTION update_task_timestamp()
RETURNS TRIGGER AS $$
BEGIN
    NEW.updated_at = CURRENT_TIMESTAMP;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;


--Функция для обновления creator_id
-- Обновленная функция set_task_creator
CREATE OR REPLACE FUNCTION set_task_creator()
RETURNS TRIGGER AS $$
BEGIN
    NEW.creator_id := current_setting('app.user_id')::UUID;
    PERFORM validate_user_exists(NEW.creator_id); -- Используем общую функцию
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- Новая функция для проверки прав изменения приватности
CREATE OR REPLACE FUNCTION check_list_privacy_change()
RETURNS TRIGGER AS $$
DECLARE
    current_user_id UUID;
BEGIN
    -- Проверка контекста пользователя
    BEGIN
        current_user_id := current_setting('app.user_id')::UUID;
    EXCEPTION 
        WHEN undefined_object THEN
            RAISE EXCEPTION 'User context is not set';
    END;

    -- Если приватность не меняется - пропускаем проверку
    IF NEW.is_private = OLD.is_private THEN
        RETURN NEW;
    END IF;

    -- Проверка прав на изменение приватности
    IF NOT EXISTS (
        SELECT 1
        FROM group_members gm
        JOIN role_permissions rp ON gm.role_id = rp.role_id
        WHERE gm.group_id = OLD.group_id
          AND gm.user_id = current_user_id
          AND rp.permission = 'edit_list'
    ) THEN
        RAISE EXCEPTION 
            'User % cannot change privacy of list %',
            current_user_id,
            OLD.list_id;
    END IF;

    RETURN NEW;
END;
$$ LANGUAGE plpgsql;


--Функция установки пользователя из JWT
CREATE OR REPLACE FUNCTION set_current_user()
RETURNS VOID AS $$
BEGIN
    -- Теперь бэкенд сам устанавливает app.user_id
    IF current_setting('app.user_id', true) IS NULL THEN
        RAISE EXCEPTION 'User context is not set';
    END IF;
END;
$$ LANGUAGE plpgsql;


-- Объединенная функция проверки групп и прав назначения
-- Обновленная функция check_task_group_consistency
CREATE OR REPLACE FUNCTION check_task_group_consistency()
RETURNS TRIGGER AS $$
DECLARE
    list_group_id INT;
    tag_group_id INT;
    target_group_id INT;
    current_user_id UUID;
    operation_type TEXT := COALESCE(TG_ARGV[0], ''); -- Защита от NULL
BEGIN
    -- 1. Проверка контекста пользователя
    BEGIN
        current_user_id := current_setting('app.user_id')::UUID;
    EXCEPTION 
        WHEN undefined_object THEN
            RAISE EXCEPTION 'User context is not set';
    END;

    -- 2. Получение групп списка и тега
    IF NEW.list_id IS NOT NULL THEN
        SELECT group_id INTO list_group_id FROM lists WHERE list_id = NEW.list_id;
    ELSE
        list_group_id := NULL;
    END IF;

    IF NEW.tag_id IS NOT NULL THEN
        SELECT group_id INTO tag_group_id FROM tags WHERE tag_id = NEW.tag_id;
    ELSE
        tag_group_id := NULL;
    END IF;

    -- 3. Определение целевой группы
    target_group_id := COALESCE(list_group_id, tag_group_id);
    
    IF target_group_id IS NULL THEN
        RAISE EXCEPTION 'Task must be linked to a list or tag';
    END IF;

    -- 4. Проверка совместимости групп
    IF list_group_id IS NOT NULL 
        AND tag_group_id IS NOT NULL 
        AND list_group_id <> tag_group_id 
    THEN
        RAISE EXCEPTION 'Group conflict: list_group=%, tag_group=%', 
            list_group_id, 
            tag_group_id;
    END IF;

    -- 5. Проверка прав назначения (только для task_assignees)
    IF operation_type = 'assign' THEN
        IF NOT EXISTS (
            SELECT 1
            FROM group_members gm
            JOIN role_permissions rp ON gm.role_id = rp.role_id
            WHERE gm.group_id = target_group_id
              AND gm.user_id = current_user_id
              AND rp.permission = 'assign_task'
        ) THEN
            RAISE EXCEPTION 
                'User % cannot assign tasks in group %', 
                current_user_id, 
                target_group_id;
        END IF;
    END IF;

    RETURN NEW;
END;
$$ LANGUAGE plpgsql;


CREATE OR REPLACE FUNCTION check_group_membership()
RETURNS TRIGGER AS $$
DECLARE
    current_user_id UUID;
    target_group_id INTEGER;
    entity_type TEXT := TG_ARGV[0];
BEGIN
    current_user_id := current_setting('app.user_id')::UUID;
    -- Определяем group_id в зависимости от сущности
    CASE entity_type
        WHEN 'list' THEN
            target_group_id := NEW.group_id;
        WHEN 'tag' THEN
            target_group_id := NEW.group_id;
		WHEN 'task' THEN
		    SELECT COALESCE(
		        (SELECT group_id FROM lists WHERE list_id = NEW.list_id),
		        (SELECT group_id FROM tags WHERE tag_id = NEW.tag_id)
		    ) INTO target_group_id;
			
            -- Запрет изменения группы через list_id/tag_id
            IF TG_OP = 'UPDATE' AND target_group_id <> COALESCE(
                (SELECT group_id FROM lists WHERE list_id = OLD.list_id),
                (SELECT group_id FROM tags WHERE tag_id = OLD.tag_id)
            ) THEN
                RAISE EXCEPTION 'Changing task group is prohibited';
            END IF;
        ELSE
            RAISE EXCEPTION 'Invalid entity type: %', entity_type;
    END CASE;

    IF NOT EXISTS (
        SELECT 1 FROM group_members
        WHERE group_id = target_group_id AND user_id = current_user_id
    ) THEN
        RAISE EXCEPTION 'User % is not a member of group %', current_user_id, target_group_id;
    END IF;

    RETURN NEW;
END;
$$ LANGUAGE plpgsql;


--Автоматизация обновления updater_id
CREATE OR REPLACE FUNCTION set_task_updater()
RETURNS TRIGGER AS $$
DECLARE
    current_user_id UUID;
BEGIN
    BEGIN
        current_user_id := current_setting('app.user_id')::UUID;
    EXCEPTION 
        WHEN undefined_object THEN
            RAISE EXCEPTION 'User context is not set';
    END;

    -- Проверка существования пользователя
    IF NOT EXISTS (
        SELECT 1 
        FROM users 
        WHERE user_id = current_user_id
    ) THEN
        RAISE EXCEPTION 'User % does not exist', current_user_id;
    END IF;

    NEW.updater_id := current_user_id;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- Обновленная функция set_assigned_by
CREATE OR REPLACE FUNCTION set_assigned_by()
RETURNS TRIGGER AS $$
BEGIN
    PERFORM check_user_context();
    NEW.assigned_by := current_setting('app.user_id')::UUID;
    PERFORM validate_user_exists(NEW.assigned_by); -- Добавлена проверка
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;


-- Проверка, что роль принадлежит той же группе, что и участник
CREATE OR REPLACE FUNCTION check_role_group()
RETURNS TRIGGER AS $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 
        FROM group_roles 
        WHERE role_id = NEW.role_id 
          AND group_id = NEW.group_id
    ) THEN
        RAISE EXCEPTION 'Role % does not belong to group %', NEW.role_id, NEW.group_id;
    END IF;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;


-- Проверка разрешения на создание задачи
CREATE OR REPLACE FUNCTION check_task_create_permission()
RETURNS TRIGGER AS $$
DECLARE
    target_group_id INTEGER;
    current_user_id UUID;
BEGIN
    PERFORM check_user_context();
    current_user_id := current_setting('app.user_id')::UUID;

    SELECT COALESCE(
        (SELECT group_id FROM lists WHERE list_id = NEW.list_id),
        (SELECT group_id FROM tags WHERE tag_id = NEW.tag_id)
    ) INTO target_group_id;

    IF NOT EXISTS (
        SELECT 1
        FROM group_members gm
        JOIN role_permissions rp ON gm.role_id = rp.role_id
        WHERE gm.group_id = target_group_id
          AND gm.user_id = current_user_id
          AND rp.permission = 'create_task'
    ) THEN
        RAISE EXCEPTION 'User % has no permission to create tasks in group %', current_user_id, target_group_id;
    END IF;

    RETURN NEW;
END;
$$ LANGUAGE plpgsql;


-- Проверка разрешения на создание списка
CREATE OR REPLACE FUNCTION check_list_create_permission()
RETURNS TRIGGER AS $$
BEGIN
    PERFORM check_user_context();
    IF NOT EXISTS (
        SELECT 1
        FROM group_members gm
        JOIN role_permissions rp ON gm.role_id = rp.role_id
        WHERE gm.group_id = NEW.group_id
          AND gm.user_id = current_setting('app.user_id')::UUID
          AND rp.permission = 'create_list'
    ) THEN
        RAISE EXCEPTION 'User has no permission to create lists in group %', NEW.group_id;
    END IF;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;


-- Проверка разрешения на создание тега
CREATE OR REPLACE FUNCTION check_tag_create_permission()
RETURNS TRIGGER AS $$
BEGIN
    PERFORM check_user_context();
    IF NOT EXISTS (
        SELECT 1
        FROM group_members gm
        JOIN role_permissions rp ON gm.role_id = rp.role_id
        WHERE gm.group_id = NEW.group_id
          AND gm.user_id = current_setting('app.user_id')::UUID
          AND rp.permission = 'create_tag'
    ) THEN
        RAISE EXCEPTION 'User has no permission to create tags in group %', NEW.group_id;
    END IF;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;


--ТРИГГЕРЫ--
--users--
CREATE TRIGGER user_after_insert
AFTER INSERT ON users
FOR EACH ROW
EXECUTE FUNCTION create_personal_group();

-- Обновленный триггер
CREATE TRIGGER group_owner_deletion
BEFORE DELETE ON users
FOR EACH ROW
EXECUTE FUNCTION transfer_group_ownership();


--tags--
CREATE TRIGGER tag_create_permission_check
BEFORE INSERT ON tags
FOR EACH ROW
EXECUTE FUNCTION check_tag_create_permission();


CREATE TRIGGER tag_group_membership
BEFORE INSERT OR UPDATE ON tags
FOR EACH ROW EXECUTE FUNCTION check_group_membership('tag');


--lists--
CREATE TRIGGER list_create_permission_check
BEFORE INSERT ON lists
FOR EACH ROW
EXECUTE FUNCTION check_list_create_permission();


CREATE TRIGGER list_group_membership
BEFORE INSERT OR UPDATE ON lists
FOR EACH ROW EXECUTE FUNCTION check_group_membership('list');


-- Триггер для таблиц приватных списков
DROP TRIGGER IF EXISTS list_privacy_before_update ON lists;
CREATE TRIGGER list_privacy_change_check
BEFORE UPDATE OF is_private ON lists
FOR EACH ROW
EXECUTE FUNCTION check_list_privacy_change();


--group_members--
CREATE TRIGGER group_members_role_check
BEFORE INSERT OR UPDATE ON group_members
FOR EACH ROW
EXECUTE FUNCTION check_role_group();


--task_assignees--
CREATE TRIGGER task_assignees_set_assigned_by
BEFORE INSERT ON task_assignees
FOR EACH ROW
EXECUTE FUNCTION set_assigned_by();

-- Обновленные триггеры с аргументами
CREATE TRIGGER task_assignee_check
BEFORE INSERT OR UPDATE ON task_assignees
FOR EACH ROW 
EXECUTE FUNCTION check_task_group_consistency('assign'); -- Аргумент 'assign'


--tasks--
-- Триггер для обновления creator_id
CREATE TRIGGER task_before_insert_creator
BEFORE INSERT ON tasks
FOR EACH ROW
EXECUTE FUNCTION set_task_creator();

-- Триггер для обновления updater_id
CREATE TRIGGER task_before_insert_updater
BEFORE INSERT ON tasks
FOR EACH ROW
EXECUTE FUNCTION set_task_updater();


-- Проверка прав на создание задачи
CREATE TRIGGER task_create_permission_check
BEFORE INSERT ON tasks
FOR EACH ROW
EXECUTE FUNCTION check_task_create_permission();


-- Проверка групповой согласованности
CREATE TRIGGER task_group_consistency
BEFORE INSERT OR UPDATE ON tasks
FOR EACH ROW 
EXECUTE FUNCTION check_task_group_consistency(); -- Без аргумента


-- Триггер для обновления задачи
CREATE TRIGGER task_before_update
BEFORE UPDATE ON tasks
FOR EACH ROW
EXECUTE FUNCTION set_task_updater();


--Триггер для tasks
CREATE TRIGGER task_permission_before_update
BEFORE UPDATE ON tasks
FOR EACH ROW
EXECUTE FUNCTION check_task_permission();


CREATE TRIGGER task_timestamp_update
BEFORE UPDATE ON tasks
FOR EACH ROW
WHEN (OLD.* IS DISTINCT FROM NEW.*)
EXECUTE FUNCTION update_task_timestamp();


-- Триггеры для таблиц, связанных со списками
CREATE TRIGGER task_list_access_check
BEFORE INSERT OR UPDATE ON tasks
FOR EACH ROW
WHEN (NEW.list_id IS NOT NULL)
EXECUTE FUNCTION check_group_membership();


CREATE TRIGGER task_group_access_check
BEFORE INSERT OR UPDATE ON tasks
FOR EACH ROW
WHEN (NEW.list_id IS NOT NULL OR NEW.tag_id IS NOT NULL)
EXECUTE FUNCTION check_group_membership('task');


-- Для удаления из таблицы tasks
CREATE TRIGGER task_before_delete
BEFORE DELETE ON tasks
FOR EACH ROW
EXECUTE FUNCTION check_task_permission();

-- Разделение триггеров для временной метки и проверки прав
DROP TRIGGER IF EXISTS task_timestamp_before_update ON tasks;



/*==== TABLES ====*/

COMMENT ON TABLE users IS 
'Пользователи системы. Содержит учетные данные и базовую информацию';

COMMENT ON COLUMN users.user_id IS 'UUID пользователя (генерируется автоматически)';
COMMENT ON COLUMN users.hashed_password IS 'Хеш пароля с использованием bcrypt';

COMMENT ON TABLE groups IS 
'Группы для организации работы. Каждый пользователь имеет персональную группу';
COMMENT ON COLUMN groups.is_personal IS 
'TRUE для персональных групп (автоматически создаются при регистрации)';

COMMENT ON TABLE group_roles IS 
'Роли в группах с набором разрешений. Примеры: "Owner", "Admin", "Member"';
COMMENT ON COLUMN group_roles.role_name IS 
'Уникальное имя роли в рамках группы (регистронезависимо)';

COMMENT ON TABLE group_members IS 
'Связь пользователей с группами и их ролями. PK: (group_id, user_id)';

COMMENT ON TABLE role_permissions IS 
'Назначение разрешений ролям. Разрешения: create_task, edit_task, ...';

COMMENT ON TABLE lists IS 
'Списки задач. Могут быть приватными (видимыми только участникам группы)';
COMMENT ON COLUMN lists.is_private IS 
'Приватный список виден только участникам группы';

COMMENT ON TABLE tags IS 
'Теги для категоризации задач. Принадлежат группам';

COMMENT ON TABLE tasks IS 
'Задачи. Обязательно привязаны к списку ИЛИ тегу';
COMMENT ON COLUMN tasks.creator_id IS 
'Автоматически устанавливается при создании (текущий пользователь)';
COMMENT ON COLUMN tasks.updater_id IS 
'Автоматически обновляется при изменении (текущий пользователь)';

COMMENT ON TABLE task_assignees IS 
'Назначение задач на пользователей. PK: (task_id, user_id)';
COMMENT ON COLUMN task_assignees.assigned_by IS 
'Кто назначил задачу (автоматически заполняется)';

/*==== FUNCTIONS ====*/

COMMENT ON FUNCTION validate_group_consistency(integer, integer) IS 
'Проверка принадлежности списка и тега к одной группе. Вызывает исключение при конфликте';

COMMENT ON FUNCTION validate_user_exists(uuid) IS 
'Проверка существования пользователя по UUID. Используется в триггерах';

COMMENT ON FUNCTION create_personal_group() IS 
'Триггерная функция: создает персональную группу при регистрации пользователя';

COMMENT ON FUNCTION check_user_context() IS 
'Проверка установки контекста пользователя (app.user_id)';

COMMENT ON FUNCTION check_task_permission() IS 
'Проверка прав на операцию с задачей: edit_task или delete_task';

COMMENT ON FUNCTION transfer_group_ownership() IS 
'Передача владения группами при удалении пользователя. Логика выбора нового владельца:
1. Поиск администраторов группы
2. Любой активный участник';

COMMENT ON FUNCTION check_task_group_consistency() IS 
'Проверка:
1. Принадлежность задачи к группе через список/тег
2. Права на назначение задач (permission assign_task)';

/*==== TRIGGERS ====*/

COMMENT ON TRIGGER user_after_insert ON users IS 
'Автоматическое создание персональной группы при регистрации';

COMMENT ON TRIGGER group_owner_deletion ON users IS 
'Перед удалением пользователя передает владение его группами';

COMMENT ON TRIGGER task_group_consistency ON tasks IS 
'Проверка перед вставкой/обновлением:
- Задача привязана к группе
- Список и тег принадлежат одной группе';

COMMENT ON TRIGGER task_timestamp_update ON tasks IS 
'Автоматическое обновление updated_at при любых изменениях задачи';

COMMENT ON TRIGGER list_privacy_change_check ON lists IS 
'Проверка прав на изменение приватности списка (permission edit_list)';

COMMENT ON TRIGGER group_members_role_check ON group_members IS 
'Проверка что роль принадлежит той же группе что и участник';
