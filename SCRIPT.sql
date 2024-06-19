-- Eliminación de tablas y secuencias existentes
drop table modelos cascade constraints;
drop table vehiculos cascade constraints;
drop table clientes cascade constraints;
drop table facturas cascade constraints;
drop table lineas_factura cascade constraints;
drop table reservas cascade constraints;

drop sequence seq_modelos;
drop sequence seq_num_fact;
drop sequence seq_reservas;

-- Creación de tablas
create table clientes(
  NIF varchar(9) primary key,
  nombre varchar(20) not null,
  ape1 varchar(20) not null,
  ape2 varchar(20) not null,
  direccion varchar(40)
);

create sequence seq_modelos;

create table modelos(
  id_modelo integer primary key,
  nombre varchar(30) not null,
  precio_cada_dia numeric(6,2) not null check (precio_cada_dia>=0)
);

create table vehiculos(
  matricula varchar(8) primary key,
  id_modelo integer not null references modelos,
  color varchar(10)
);

create sequence seq_reservas;
create table reservas(
  idReserva integer primary key,
  cliente varchar(9) references clientes,
  matricula varchar(8) references vehiculos,
  fecha_ini date not null,
  fecha_fin date,
  check (fecha_fin >= fecha_ini)
);

create sequence seq_num_fact;
create table facturas(
  nroFactura integer primary key,
  importe numeric(8, 2),
  cliente varchar(9) not null references clientes
);

create table lineas_factura(
  nroFactura integer references facturas,
  concepto char(40),
  importe numeric(7, 2),
  primary key (nroFactura, concepto)
);

-- Procedimiento para alquilar un coche
create or replace procedure alquilar_coche(
  arg_NIF_cliente varchar,
  arg_matricula varchar,
  arg_fecha_ini date,
  arg_fecha_fin date
) is
  v_precio_dia modelos.precio_cada_dia%type;
  v_nombre_modelo modelos.nombre%type;
  v_count integer;
  v_n_dias integer;
  v_importe numeric(8, 2);
  v_cliente_count integer;
begin
  -- Comprobar si la fecha de inicio no es posterior a la fecha fin
  if arg_fecha_ini > arg_fecha_fin then
    raise_application_error(-20001, 'No pueden realizarse alquileres por períodos inferiores a 1 día');
  end if;

  -- Seleccionar el vehículo y bloquearlo
  begin
    select m.precio_cada_dia, m.nombre
    into v_precio_dia, v_nombre_modelo
    from vehiculos v
    join modelos m on v.id_modelo = m.id_modelo
    where v.matricula = arg_matricula
    for update of v.matricula;

    -- Si no se encuentra el vehículo, lanzar error
    exception
      when no_data_found then
        raise_application_error(-20002, 'Vehiculo inexistente.');
  end;
  
  -- Comprobar si ya existe una reserva solapada para el vehículo
  select count(*)
  into v_count
  from reservas
  where matricula = arg_matricula
    and (
      (arg_fecha_ini between fecha_ini and fecha_fin) or
      (arg_fecha_fin between fecha_ini and fecha_fin) or
      (fecha_ini between arg_fecha_ini and arg_fecha_fin) or
      (fecha_fin between arg_fecha_ini and arg_fecha_fin)
    );

  if v_count > 0 then
    raise_application_error(-20003, 'El vehículo no está disponible para esas fechas.');
  end if;

  -- Validar la existencia del cliente
  select count(*)
  into v_cliente_count
  from clientes
  where NIF = arg_NIF_cliente;

  if v_cliente_count = 0 then
    raise_application_error(-20004, 'Cliente inexistente.');
  end if;

  -- Insertar la reserva
  insert into reservas(idReserva, cliente, matricula, fecha_ini, fecha_fin)
  values (seq_reservas.nextval, arg_NIF_cliente, arg_matricula, arg_fecha_ini, arg_fecha_fin);

  -- Calcular el número de días y el importe
  v_n_dias := arg_fecha_fin - arg_fecha_ini;
  v_importe := v_n_dias * v_precio_dia;

  -- Crear la factura
  insert into facturas(nroFactura, importe, cliente)
  values (seq_num_fact.nextval, v_importe, arg_NIF_cliente);

  -- Crear la línea de factura
  insert into lineas_factura(nroFactura, concepto, importe)
  values (seq_num_fact.currval, v_n_dias || ' días de alquiler vehículo modelo ' || v_nombre_modelo, v_importe);

end;
/


    -- P6a: ¿Por qué crees que se hace la recomendación del paso 2?
    -- La recomendación del paso 2 es crucial para asegurar que estamos trabajando con los datos correctos y que estamos bloqueando el recurso adecuado. En este caso, necesitamos bloquear el vehículo específico que se va a alquilar para evitar que otros procesos puedan realizar operaciones concurrentes sobre el mismo vehículo. Esto evita condiciones de carrera y garantiza que el vehículo esté disponible para el cliente que realiza la reserva. 
    -- Cuando realizamos una operación de alquiler, es fundamental que el vehículo en cuestión no pueda ser reservado por otro cliente simultáneamente. Al usar la cláusula FOR UPDATE en la consulta, bloqueamos el registro del vehículo, lo que significa que cualquier intento de modificación o reserva del mismo vehículo por otra transacción será bloqueado hasta que la transacción actual se complete. Esto asegura que no haya conflictos ni inconsistencias en la base de datos.
    -- Sin esta medida, podríamos enfrentarnos a situaciones donde múltiples clientes intentan reservar el mismo vehículo al mismo tiempo, lo que podría resultar en múltiples reservas conflictivas y datos corruptos. Por lo tanto, esta recomendación es una práctica estándar para manejar la concurrencia y mantener la integridad de los datos en aplicaciones de bases de datos.

    -- P6b: El resultado de la SELECT del paso 4, ¿sigue siendo fiable en el paso 5?, ¿por qué?
    -- Sí, el resultado de la SELECT del paso 4 sigue siendo fiable en el paso 5. Esto es porque la transacción ha bloqueado el registro del vehículo desde el paso 2 con la cláusula FOR UPDATE. Este bloqueo garantiza que ningún otro proceso pueda modificar el estado del vehículo mientras la transacción actual está en curso.
    -- En términos de concurrencia, el bloqueo aplicado en el paso 2 asegura que el estado del vehículo y cualquier reserva existente no puedan ser alterados por otras transacciones hasta que la transacción actual se complete. Así, cuando llegamos al paso 5, podemos estar seguros de que los datos que estamos utilizando son coherentes y no han sido modificados por otras operaciones concurrentes.
    -- Este enfoque asegura que cualquier decisión basada en el estado del vehículo y sus reservas en el paso 4 sigue siendo válida y precisa en el paso 5, proporcionando una capa adicional de seguridad y precisión en nuestras operaciones de base de datos.

    -- P6c: En este paso, la ejecución concurrente del mismo procedimiento ALQUILA con, quizás otros o los mismos argumentos, ¿podría habernos añadido una reserva no recogida en esa SELECT que fuese incompatible con nuestra reserva?, ¿por qué?
    -- No, la ejecución concurrente del mismo procedimiento ALQUILA no podría añadir una reserva no recogida en esa SELECT debido al bloqueo aplicado con FOR UPDATE. Cuando un registro es bloqueado por una transacción, ninguna otra transacción puede modificarlo hasta que el bloqueo se libere (es decir, hasta que la transacción se complete o se deshaga). 
    -- Esto significa que cualquier intento de reservar el mismo vehículo por otra transacción sería bloqueado y tendría que esperar a que la transacción actual se complete. Este mecanismo de bloqueo asegura que no se añadan reservas solapadas mientras estamos realizando nuestras operaciones. 
    -- El uso de FOR UPDATE es una técnica fundamental en bases de datos para manejar la concurrencia y asegurar la integridad de los datos. Garantiza que los registros críticos, como los de los vehículos en este caso, estén protegidos contra modificaciones concurrentes, previniendo conflictos y asegurando que cada operación de reserva se maneje de manera aislada y segura.

    -- P6d: ¿Qué tipo de estrategia de programación has empleado en tu código? ¿Cómo se refleja esto en tu código?
    -- En mi código he empleado una estrategia de programación defensiva. La programación defensiva se trata de anticipar problemas y errores antes de que ocurran y asegurarse de que el sistema puede manejarlos de manera adecuada sin fallar. En este procedimiento, esto se refleja en varias prácticas clave.
    -- Primero, hay múltiples verificaciones de condiciones antes de realizar operaciones críticas. Por ejemplo, se valida que la fecha de inicio no sea posterior a la fecha de fin antes de proceder. Esta validación temprana evita que se realicen operaciones inválidas.
    -- Segundo, se utiliza el manejo de excepciones para capturar y manejar errores específicos, como cuando no se encuentra un vehículo o un cliente, o cuando hay reservas solapadas. Al capturar estas excepciones y proporcionar mensajes de error claros, se evita que el sistema falle de manera inesperada y se proporciona información útil para corregir el problema.
    -- Tercero, se emplean bloqueos (FOR UPDATE) para asegurar la integridad de los datos durante la transacción, evitando condiciones de carrera y garantizando que los datos permanecen consistentes incluso en entornos concurrentes.
    -- Esta estrategia defensiva asegura que el sistema sea robusto y fiable, anticipando y manejando errores de manera controlada, lo que facilita el mantenimiento y mejora la experiencia del usuario.


-- Procedimiento para resetear secuencias
--From https://stackoverflow.com/questions/51470/how-do-i-reset-a-sequence-in-oracle
create or replace procedure reset_seq(p_seq_name varchar) is
  l_val number;
begin
  execute immediate 'select ' || p_seq_name || '.nextval from dual' INTO l_val;
  execute immediate 'alter sequence ' || p_seq_name || ' increment by -' || l_val || ' minvalue 0';
  execute immediate 'select ' || p_seq_name || '.nextval from dual' INTO l_val;
  execute immediate 'alter sequence ' || p_seq_name || ' increment by 1 minvalue 0';
end;
/

-- Procedimiento para inicializar datos de prueba
create or replace procedure inicializa_test is
begin
  reset_seq('seq_modelos');
  reset_seq('seq_num_fact');
  reset_seq('seq_reservas');
  
  delete from lineas_factura;
  delete from facturas;
  delete from reservas;
  delete from vehiculos;
  delete from modelos;
  delete from clientes;
  
  insert into clientes values ('12345678A', 'Pepe', 'Perez', 'Porras', 'C/Perezoso n1');
  insert into clientes values ('11111111B', 'Beatriz', 'Barbosa', 'Bernardez', 'C/Barriocanal n1');
  
  insert into modelos values (seq_modelos.nextval, 'Renault Clio Gasolina', 15);
  insert into vehiculos values ('1234-ABC', seq_modelos.currval, 'VERDE');

  insert into modelos values (seq_modelos.nextval, 'Renault Clio Gasoil', 16);
  insert into vehiculos values ('1111-ABC', seq_modelos.currval, 'VERDE');
  insert into vehiculos values ('2222-ABC', seq_modelos.currval, 'GRIS');
  
  commit;
end;
/

-- Ejecución del procedimiento de inicialización
exec inicializa_test;

-- Procedimiento de pruebas
create or replace procedure test_alquila_coches is
begin
  -- Caso 1: Todo correcto
  -- Este test verifica que el procedimiento realiza correctamente la reserva y crea la factura correspondiente cuando todos los valores son correctos.
  begin
    inicializa_test;
    begin
      -- Intentar realizar una reserva con valores correctos
      alquilar_coche('12345678A', '1234-ABC', to_date('2024-06-10', 'YYYY-MM-DD'), to_date('2024-06-12', 'YYYY-MM-DD'));
      dbms_output.put_line('Caso 1: Reserva realizada correctamente');
    exception
      when others then
        dbms_output.put_line('Caso 1: Error inesperado - ' || sqlerrm);
    end;
  end;

  -- Caso 2: Número de días negativo
  -- Este test verifica que el procedimiento arroja un error cuando la fecha de inicio es posterior a la fecha de fin.
  begin
    inicializa_test;
    begin
      -- Intentar alquilar un coche con una fecha de fin anterior a la fecha de inicio
      alquilar_coche('12345678A', '1234-ABC', to_date('2024-06-10', 'YYYY-MM-DD'), to_date('2024-06-09', 'YYYY-MM-DD'));
    exception
      when others then
        if sqlcode = -20001 then
          dbms_output.put_line('Caso 2: Correcto - ' || sqlerrm);
        else
          dbms_output.put_line('Caso 2: Incorrecto - ' || sqlerrm);
        end if;
    end;
  end;

  -- Caso 3: Vehículo inexistente
  -- Este test verifica que el procedimiento arroja un error cuando se intenta alquilar un vehículo que no existe en la base de datos.
  begin
    inicializa_test;
    begin
      -- Intentar alquilar un coche con una matrícula que no existe
      alquilar_coche('12345678A', '9999-XYZ', to_date('2024-06-10', 'YYYY-MM-DD'), to_date('2024-06-12', 'YYYY-MM-DD'));
    exception
      when others then
        if sqlcode = -20002 then
          dbms_output.put_line('Caso 3: Correcto - ' || sqlerrm);
        else
          dbms_output.put_line('Caso 3: Incorrecto - ' || sqlerrm);
        end if;
    end;
  end;

  -- Caso 4: Intentar alquilar un coche ya alquilado
  -- 4.1: La fecha de inicio del alquiler está dentro de una reserva
  -- Este test verifica que el procedimiento arroja un error cuando se intenta alquilar un coche en una fecha de inicio que se solapa con una reserva existente.
  begin
    inicializa_test;
    begin
      -- Crear una reserva inicial
      alquilar_coche('12345678A', '1234-ABC', to_date('2024-06-10', 'YYYY-MM-DD'), to_date('2024-06-15', 'YYYY-MM-DD'));
      -- Intentar crear una reserva solapada
      alquilar_coche('11111111B', '1234-ABC', to_date('2024-06-14', 'YYYY-MM-DD'), to_date('2024-06-16', 'YYYY-MM-DD'));
    exception
      when others then
        if sqlcode = -20003 then
          dbms_output.put_line('Caso 4.1: Correcto - ' || sqlerrm);
        else
          dbms_output.put_line('Caso 4.1: Incorrecto - ' || sqlerrm);
        end if;
    end;
  end;

  -- 4.2: La fecha de fin del alquiler está dentro de una reserva
  -- Este test verifica que el procedimiento arroja un error cuando se intenta alquilar un coche en una fecha de fin que se solapa con una reserva existente.
  begin
    inicializa_test;
    begin
      -- Crear una reserva inicial
      alquilar_coche('12345678A', '1234-ABC', to_date('2024-06-10', 'YYYY-MM-DD'), to_date('2024-06-15', 'YYYY-MM-DD'));
      -- Intentar crear una reserva solapada
      alquilar_coche('11111111B', '1234-ABC', to_date('2024-06-09', 'YYYY-MM-DD'), to_date('2024-06-11', 'YYYY-MM-DD'));
    exception
      when others then
        if sqlcode = -20003 then
          dbms_output.put_line('Caso 4.2: Correcto - ' || sqlerrm);
        else
          dbms_output.put_line('Caso 4.2: Incorrecto - ' || sqlerrm);
        end if;
    end;
  end;

  -- 4.3: El intervalo del alquiler está dentro de una reserva
  -- Este test verifica que el procedimiento arroja un error cuando se intenta alquilar un coche en un intervalo de fechas que está completamente dentro de una reserva existente.
  begin
    inicializa_test;
    begin
      -- Crear una reserva inicial
      alquilar_coche('12345678A', '1234-ABC', to_date('2024-06-10', 'YYYY-MM-DD'), to_date('2024-06-15', 'YYYY-MM-DD'));
      -- Intentar crear una reserva solapada
      alquilar_coche('11111111B', '1234-ABC', to_date('2024-06-11', 'YYYY-MM-DD'), to_date('2024-06-14', 'YYYY-MM-DD'));
    exception
      when others then
        if sqlcode = -20003 then
          dbms_output.put_line('Caso 4.3: Correcto - ' || sqlerrm);
        else
          dbms_output.put_line('Caso 4.3: Incorrecto - ' || sqlerrm);
        end if;
    end;
  end;

  -- Caso 5: Cliente inexistente
  -- Este test verifica que el procedimiento arroja un error cuando se intenta alquilar un coche para un cliente que no existe en la base de datos.
  begin
    inicializa_test;
    begin
      -- Intentar alquilar un coche con un NIF de cliente que no existe
      alquilar_coche('99999999Z', '1234-ABC', to_date('2024-06-10', 'YYYY-MM-DD'), to_date('2024-06-12', 'YYYY-MM-DD'));
    exception
      when others then
        if sqlcode = -20004 then
          dbms_output.put_line('Caso 5: Correcto - ' || sqlerrm);
        else
          dbms_output.put_line('Caso 5: Incorrecto - ' || sqlerrm);
        end if;
    end;
  end;


end;
/

set serveroutput on
exec test_alquila_coches;


-- Nueva batería de tests del enunciado
create or replace procedure bateria_tests is
begin
  -- T1: Realizar una reserva con valores correctos
  begin
    dbms_output.put_line('T1: Comprobando...');
    inicializa_test;
    begin
      -- Intentar realizar una reserva con valores correctos
      alquilar_coche('12345678A', '1234-ABC', to_date('2024-06-10', 'YYYY-MM-DD'), to_date('2024-06-12', 'YYYY-MM-DD'));
      dbms_output.put_line('T1: Reserva realizada correctamente');
    exception
      when others then
        dbms_output.put_line('T1: Error inesperado - ' || sqlerrm);
    end;
  end;

  -- T2: Reserva de duración inferior a 1 día
  begin
    dbms_output.put_line('T2: Comprobando...');
    inicializa_test;
    begin
      -- Intentar alquilar un coche con una fecha de fin anterior a la fecha de inicio
      alquilar_coche('12345678A', '1234-ABC', to_date('2024-06-10', 'YYYY-MM-DD'), to_date('2024-06-09', 'YYYY-MM-DD'));
    exception
      when others then
        if sqlcode = -20001 then
          dbms_output.put_line('T2: Correcto - ' || sqlerrm);
        else
          dbms_output.put_line('T2: Incorrecto - ' || sqlerrm);
        end if;
    end;
  end;

  -- T3: Vehículo inexistente
  begin
    dbms_output.put_line('T3: Comprobando...');
    inicializa_test;
    begin
      -- Intentar alquilar un coche con una matrícula que no existe
      alquilar_coche('12345678A', '9999-XYZ', to_date('2024-06-10', 'YYYY-MM-DD'), to_date('2024-06-12', 'YYYY-MM-DD'));
    exception
      when others then
        if sqlcode = -20002 then
          dbms_output.put_line('T3: Correcto - ' || sqlerrm);
        else
          dbms_output.put_line('T3: Incorrecto - ' || sqlerrm);
        end if;
    end;
  end;

  -- T4: Vehículo no disponible en las fechas
  begin
    dbms_output.put_line('T4: Comprobando...');
    inicializa_test;
    begin
      -- Crear una reserva inicial
      alquilar_coche('12345678A', '1234-ABC', to_date('2024-06-10', 'YYYY-MM-DD'), to_date('2024-06-15', 'YYYY-MM-DD'));
      -- Intentar crear una reserva solapada
      alquilar_coche('11111111B', '1234-ABC', to_date('2024-06-14', 'YYYY-MM-DD'), to_date('2024-06-16', 'YYYY-MM-DD'));
    exception
      when others then
        if sqlcode = -20003 then
          dbms_output.put_line('T4.1: Correcto - ' || sqlerrm);
        else
          dbms_output.put_line('T4.1: Incorrecto - ' || sqlerrm);
        end if;
    end;

    inicializa_test;
    begin
      -- Crear una reserva inicial
      alquilar_coche('12345678A', '1234-ABC', to_date('2024-06-10', 'YYYY-MM-DD'), to_date('2024-06-15', 'YYYY-MM-DD'));
      -- Intentar crear una reserva solapada
      alquilar_coche('11111111B', '1234-ABC', to_date('2024-06-09', 'YYYY-MM-DD'), to_date('2024-06-11', 'YYYY-MM-DD'));
    exception
      when others then
        if sqlcode = -20003 then
          dbms_output.put_line('T4.2: Correcto - ' || sqlerrm);
        else
          dbms_output.put_line('T4.2: Incorrecto - ' || sqlerrm);
        end if;
    end;

    inicializa_test;
    begin
      -- Crear una reserva inicial
      alquilar_coche('12345678A', '1234-ABC', to_date('2024-06-10', 'YYYY-MM-DD'), to_date('2024-06-15', 'YYYY-MM-DD'));
      -- Intentar crear una reserva solapada
      alquilar_coche('11111111B', '1234-ABC', to_date('2024-06-11', 'YYYY-MM-DD'), to_date('2024-06-14', 'YYYY-MM-DD'));
    exception
      when others then
        if sqlcode = -20003 then
          dbms_output.put_line('T4.3: Correcto - ' || sqlerrm);
        else
          dbms_output.put_line('T4.3: Incorrecto - ' || sqlerrm);
        end if;
    end;
  end;

  -- T5: Cliente inexistente
  begin
    dbms_output.put_line('T5: Comprobando...');
    inicializa_test;
    begin
      -- Intentar alquilar un coche con un NIF de cliente que no existe
      alquilar_coche('99999999Z', '1234-ABC', to_date('2024-06-10', 'YYYY-MM-DD'), to_date('2024-06-12', 'YYYY-MM-DD'));
    exception
      when others then
        if sqlcode = -20004 then
          dbms_output.put_line('T5: Correcto - ' || sqlerrm);
        else
          dbms_output.put_line('T5: Incorrecto - ' || sqlerrm);
        end if;
    end;
  end;

  -- T6: Cliente sin suficiente saldo
  begin
    dbms_output.put_line('T6: Comprobando...');
    inicializa_test;
    begin
      -- Intentar alquilar un coche con un cliente que no tiene suficiente saldo
      alquilar_coche('11111111B', '1234-ABC', to_date('2024-06-10', 'YYYY-MM-DD'), to_date('2024-06-20', 'YYYY-MM-DD'));
    exception
      when others then
        if sqlcode = -20005 then
          dbms_output.put_line('T6: Correcto - ' || sqlerrm);
        else
          dbms_output.put_line('T6: Incorrecto - ' || sqlerrm);
        end if;
    end;
  end;
end;
/

set serveroutput on
exec bateria_tests;
