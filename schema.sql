--
-- PostgreSQL database dump
--

-- Dumped from database version 16.9 (Ubuntu 16.9-0ubuntu0.24.04.1)
-- Dumped by pg_dump version 16.9 (Ubuntu 16.9-0ubuntu0.24.04.1)

SET statement_timeout = 0;
SET lock_timeout = 0;
SET idle_in_transaction_session_timeout = 0;
SET client_encoding = 'UTF8';
SET standard_conforming_strings = on;
SELECT pg_catalog.set_config('search_path', '', false);
SET check_function_bodies = false;
SET xmloption = content;
SET client_min_messages = warning;
SET row_security = off;

--
-- Name: pgcrypto; Type: EXTENSION; Schema: -; Owner: -
--

CREATE EXTENSION IF NOT EXISTS pgcrypto WITH SCHEMA public;


--
-- Name: EXTENSION pgcrypto; Type: COMMENT; Schema: -; Owner: 
--

COMMENT ON EXTENSION pgcrypto IS 'cryptographic functions';


--
-- Name: movement_enum; Type: TYPE; Schema: public; Owner: postgres
--

CREATE TYPE public.movement_enum AS ENUM (
    'IN',
    'OUT',
    'TRANSFER',
    'WASTE',
    'RETURN',
    'ADJUSTMENT'
);


ALTER TYPE public.movement_enum OWNER TO postgres;

--
-- Name: update_stock_after_movement(); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION public.update_stock_after_movement() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
BEGIN
  -- Agar 'in' bo‘lsa → qo‘shamiz
  IF NEW.movement_type = 'in' THEN
    -- Avval mavjudligini tekshiramiz
    INSERT INTO stock_levels(branch_id, ingredient_id, qty, updated_at)
    VALUES (NEW.branch_id, NEW.ingredient_id, NEW.qty, NOW())
    ON CONFLICT (branch_id, ingredient_id) 
    DO UPDATE SET qty = stock_levels.qty + EXCLUDED.qty,
                  updated_at = NOW();

  -- Agar 'out' bo‘lsa → ayiramiz
  ELSIF NEW.movement_type = 'out' THEN
    UPDATE stock_levels
    SET qty = qty - NEW.qty,
        updated_at = NOW()
    WHERE branch_id = NEW.branch_id
      AND ingredient_id = NEW.ingredient_id;
  END IF;

  RETURN NEW;
END;
$$;


ALTER FUNCTION public.update_stock_after_movement() OWNER TO postgres;

--
-- Name: update_stock_levels(); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION public.update_stock_levels() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
BEGIN
    -- IN va RETURN → qo‘shish
    IF NEW.movement_type = 'IN' OR NEW.movement_type = 'RETURN' THEN
        INSERT INTO stock_levels(branch_id, ingredient_id, qty, updated_at)
        VALUES (NEW.branch_id, NEW.ingredient_id, NEW.qty, NOW())
        ON CONFLICT (branch_id, ingredient_id)
        DO UPDATE SET qty = stock_levels.qty + EXCLUDED.qty,
                      updated_at = NOW();

    -- OUT va WASTE → ayirish
    ELSIF NEW.movement_type = 'OUT' OR NEW.movement_type = 'WASTE' THEN
        UPDATE stock_levels
        SET qty = stock_levels.qty - NEW.qty,
            updated_at = NOW()
        WHERE branch_id = NEW.branch_id
          AND ingredient_id = NEW.ingredient_id;

    -- ADJUSTMENT → musbat yoki manfiy qiymatni qo‘shish
    ELSIF NEW.movement_type = 'ADJUSTMENT' THEN
        UPDATE stock_levels
        SET qty = stock_levels.qty + NEW.qty,
            updated_at = NOW()
        WHERE branch_id = NEW.branch_id
          AND ingredient_id = NEW.ingredient_id;

    -- TRANSFER → manbadan ayirish va qabul qiluvchiga qo‘shish
    ELSIF NEW.movement_type = 'TRANSFER' THEN
        -- manbadan ayiramiz
        UPDATE stock_levels
        SET qty = stock_levels.qty - NEW.qty,
            updated_at = NOW()
        WHERE branch_id = NEW.branch_id
          AND ingredient_id = NEW.ingredient_id;

        -- qabul qiluvchiga qo‘shamiz
        INSERT INTO stock_levels(branch_id, ingredient_id, qty, updated_at)
        VALUES (NEW.to_branch_id, NEW.ingredient_id, NEW.qty, NOW())
        ON CONFLICT (branch_id, ingredient_id)
        DO UPDATE SET qty = stock_levels.qty + EXCLUDED.qty,
                      updated_at = NOW();
    END IF;

    RETURN NEW;
END;
$$;


ALTER FUNCTION public.update_stock_levels() OWNER TO postgres;

--
-- Name: validate_stock_before_deduction(); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION public.validate_stock_before_deduction() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
DECLARE
    available_qty numeric;
BEGIN
    -- Faqat chiqim bo‘ladigan harakatlar uchun
    IF NEW.movement_type IN ('OUT', 'TRANSFER', 'WASTE') THEN
        SELECT qty INTO available_qty
        FROM stock_levels
        WHERE branch_id = NEW.branch_id
          AND ingredient_id = NEW.ingredient_id
        FOR UPDATE;

        -- Omborda yo‘q bo‘lsa
        IF available_qty IS NULL THEN
            RAISE EXCEPTION 'Omborda ingredient mavjud emas: branch=%, ingredient=%', 
                NEW.branch_id, NEW.ingredient_id;
        END IF;

        -- Yetarli emas bo‘lsa
        IF available_qty < NEW.qty THEN
            RAISE EXCEPTION 'Omborda yetarli emas: branch=%, ingredient=%, mavjud=%, kerak=%',
                NEW.branch_id, NEW.ingredient_id, available_qty, NEW.qty;
        END IF;
    END IF;

    RETURN NEW;
END;
$$;


ALTER FUNCTION public.validate_stock_before_deduction() OWNER TO postgres;

SET default_tablespace = '';

SET default_table_access_method = heap;

--
-- Name: branches; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.branches (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    name character varying NOT NULL
);


ALTER TABLE public.branches OWNER TO postgres;

--
-- Name: ingredients; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.ingredients (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    name character varying NOT NULL,
    unit character varying NOT NULL,
    cost_price numeric(12,2) DEFAULT 0
);


ALTER TABLE public.ingredients OWNER TO postgres;

--
-- Name: inventory_movements; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.inventory_movements (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    branch_id uuid,
    ingredient_id uuid,
    qty numeric NOT NULL,
    movement_type public.movement_enum NOT NULL,
    created_at timestamp without time zone DEFAULT now(),
    to_branch_id uuid
);


ALTER TABLE public.inventory_movements OWNER TO postgres;

--
-- Name: product_ingredients; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.product_ingredients (
    product_id uuid NOT NULL,
    ingredient_id uuid NOT NULL,
    qty numeric NOT NULL
);


ALTER TABLE public.product_ingredients OWNER TO postgres;

--
-- Name: products; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.products (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    name character varying NOT NULL,
    sku character varying NOT NULL,
    sale_price numeric(12,2) DEFAULT 0
);


ALTER TABLE public.products OWNER TO postgres;

--
-- Name: stock_levels; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.stock_levels (
    branch_id uuid NOT NULL,
    ingredient_id uuid NOT NULL,
    qty numeric DEFAULT 0 NOT NULL,
    updated_at timestamp without time zone DEFAULT now()
);


ALTER TABLE public.stock_levels OWNER TO postgres;

--
-- Name: branches branches_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.branches
    ADD CONSTRAINT branches_pkey PRIMARY KEY (id);


--
-- Name: ingredients ingredients_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.ingredients
    ADD CONSTRAINT ingredients_pkey PRIMARY KEY (id);


--
-- Name: inventory_movements inventory_movements_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.inventory_movements
    ADD CONSTRAINT inventory_movements_pkey PRIMARY KEY (id);


--
-- Name: product_ingredients product_ingredients_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.product_ingredients
    ADD CONSTRAINT product_ingredients_pkey PRIMARY KEY (product_id, ingredient_id);


--
-- Name: products products_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.products
    ADD CONSTRAINT products_pkey PRIMARY KEY (id);


--
-- Name: products products_sku_key; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.products
    ADD CONSTRAINT products_sku_key UNIQUE (sku);


--
-- Name: stock_levels stock_levels_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.stock_levels
    ADD CONSTRAINT stock_levels_pkey PRIMARY KEY (branch_id, ingredient_id);


--
-- Name: inventory_movements trg_update_stock_levels; Type: TRIGGER; Schema: public; Owner: postgres
--

CREATE TRIGGER trg_update_stock_levels AFTER INSERT ON public.inventory_movements FOR EACH ROW EXECUTE FUNCTION public.update_stock_levels();


--
-- Name: inventory_movements trg_validate_stock_before_deduction; Type: TRIGGER; Schema: public; Owner: postgres
--

CREATE TRIGGER trg_validate_stock_before_deduction BEFORE INSERT ON public.inventory_movements FOR EACH ROW EXECUTE FUNCTION public.validate_stock_before_deduction();


--
-- Name: inventory_movements inventory_movements_branch_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.inventory_movements
    ADD CONSTRAINT inventory_movements_branch_id_fkey FOREIGN KEY (branch_id) REFERENCES public.branches(id);


--
-- Name: inventory_movements inventory_movements_ingredient_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.inventory_movements
    ADD CONSTRAINT inventory_movements_ingredient_id_fkey FOREIGN KEY (ingredient_id) REFERENCES public.ingredients(id);


--
-- Name: product_ingredients product_ingredients_ingredient_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.product_ingredients
    ADD CONSTRAINT product_ingredients_ingredient_id_fkey FOREIGN KEY (ingredient_id) REFERENCES public.ingredients(id);


--
-- Name: product_ingredients product_ingredients_product_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.product_ingredients
    ADD CONSTRAINT product_ingredients_product_id_fkey FOREIGN KEY (product_id) REFERENCES public.products(id);


--
-- Name: stock_levels stock_levels_branch_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.stock_levels
    ADD CONSTRAINT stock_levels_branch_id_fkey FOREIGN KEY (branch_id) REFERENCES public.branches(id);


--
-- Name: stock_levels stock_levels_ingredient_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.stock_levels
    ADD CONSTRAINT stock_levels_ingredient_id_fkey FOREIGN KEY (ingredient_id) REFERENCES public.ingredients(id);


--
-- PostgreSQL database dump complete
--

