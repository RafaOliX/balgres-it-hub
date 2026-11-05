--
-- PostgreSQL database dump
--

\restrict 6X8mAZhzIDA7xt2wX2EQwcnewFELRjFz1vySVZrd9piqHfeU4wFirxxKaGqhTVG

-- Dumped from database version 16.15
-- Dumped by pg_dump version 16.15

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

SET default_tablespace = '';

SET default_table_access_method = heap;

--
-- Name: it_asset_history; Type: TABLE; Schema: public; Owner: inventario
--

CREATE TABLE public.it_asset_history (
    id integer NOT NULL,
    asset_id integer NOT NULL,
    field_name character varying(64) NOT NULL,
    old_value character varying,
    new_value character varying,
    changed_by character varying(64) NOT NULL,
    changed_at timestamp with time zone NOT NULL
);


ALTER TABLE public.it_asset_history OWNER TO inventario;

--
-- Name: it_asset_history_id_seq; Type: SEQUENCE; Schema: public; Owner: inventario
--

CREATE SEQUENCE public.it_asset_history_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE public.it_asset_history_id_seq OWNER TO inventario;

--
-- Name: it_asset_history_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: inventario
--

ALTER SEQUENCE public.it_asset_history_id_seq OWNED BY public.it_asset_history.id;


--
-- Name: it_asset_images; Type: TABLE; Schema: public; Owner: inventario
--

CREATE TABLE public.it_asset_images (
    id integer NOT NULL,
    asset_id integer NOT NULL,
    filename character varying(256) NOT NULL,
    created_at timestamp with time zone
);


ALTER TABLE public.it_asset_images OWNER TO inventario;

--
-- Name: it_asset_images_id_seq; Type: SEQUENCE; Schema: public; Owner: inventario
--

CREATE SEQUENCE public.it_asset_images_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE public.it_asset_images_id_seq OWNER TO inventario;

--
-- Name: it_asset_images_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: inventario
--

ALTER SEQUENCE public.it_asset_images_id_seq OWNED BY public.it_asset_images.id;


--
-- Name: it_assets; Type: TABLE; Schema: public; Owner: inventario
--

CREATE TABLE public.it_assets (
    id integer NOT NULL,
    asset_tag character varying(64) NOT NULL,
    category character varying(64) NOT NULL,
    brand character varying(64) NOT NULL,
    model character varying(128) NOT NULL,
    serial_number character varying(128) NOT NULL,
    location character varying(128),
    status character varying(32),
    notes character varying,
    image_path character varying(256),
    quantity integer DEFAULT 1,
    unit character varying(32) DEFAULT 'Unidad'::character varying,
    assigned_to character varying(128)
);


ALTER TABLE public.it_assets OWNER TO inventario;

--
-- Name: it_assets_id_seq; Type: SEQUENCE; Schema: public; Owner: inventario
--

CREATE SEQUENCE public.it_assets_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE public.it_assets_id_seq OWNER TO inventario;

--
-- Name: it_assets_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: inventario
--

ALTER SEQUENCE public.it_assets_id_seq OWNED BY public.it_assets.id;


--
-- Name: it_asset_history id; Type: DEFAULT; Schema: public; Owner: inventario
--

ALTER TABLE ONLY public.it_asset_history ALTER COLUMN id SET DEFAULT nextval('public.it_asset_history_id_seq'::regclass);


--
-- Name: it_asset_images id; Type: DEFAULT; Schema: public; Owner: inventario
--

ALTER TABLE ONLY public.it_asset_images ALTER COLUMN id SET DEFAULT nextval('public.it_asset_images_id_seq'::regclass);


--
-- Name: it_assets id; Type: DEFAULT; Schema: public; Owner: inventario
--

ALTER TABLE ONLY public.it_assets ALTER COLUMN id SET DEFAULT nextval('public.it_assets_id_seq'::regclass);


--
-- Data for Name: it_asset_history; Type: TABLE DATA; Schema: public; Owner: inventario
--

COPY public.it_asset_history (id, asset_id, field_name, old_value, new_value, changed_by, changed_at) FROM stdin;
5	7	CREATED	\N	MON-001	admin	2026-11-05 18:31:56.924536+00
6	8	CREATED	\N	MON	admin	2026-11-05 20:06:20.648393+00
7	8	asset_tag	MON	MON-	admin	2026-11-05 20:06:28.810611+00
\.


--
-- Data for Name: it_asset_images; Type: TABLE DATA; Schema: public; Owner: inventario
--

COPY public.it_asset_images (id, asset_id, filename, created_at) FROM stdin;
7	7	d7f6b7ad7073420c9018da377575d995.jpg	2026-11-05 18:31:57.579968+00
8	7	0e246b0c04854d2e8b5a0c20a7179759.jpg	2026-11-05 18:31:57.585841+00
\.


--
-- Data for Name: it_assets; Type: TABLE DATA; Schema: public; Owner: inventario
--

COPY public.it_assets (id, asset_tag, category, brand, model, serial_number, location, status, notes, image_path, quantity, unit, assigned_to) FROM stdin;
7	MON-001	Monitor	DELL		NO	INFORMÁTICA	Operativo	está buena pero la pantalla está un poco sucia	\N	1	Unidad	\N
8	MON-	utp	x	x	x	x	Operativo	x	\N	1	Unidad	\N
\.


--
-- Name: it_asset_history_id_seq; Type: SEQUENCE SET; Schema: public; Owner: inventario
--

SELECT pg_catalog.setval('public.it_asset_history_id_seq', 7, true);


--
-- Name: it_asset_images_id_seq; Type: SEQUENCE SET; Schema: public; Owner: inventario
--

SELECT pg_catalog.setval('public.it_asset_images_id_seq', 8, true);


--
-- Name: it_assets_id_seq; Type: SEQUENCE SET; Schema: public; Owner: inventario
--

SELECT pg_catalog.setval('public.it_assets_id_seq', 8, true);


--
-- Name: it_asset_history it_asset_history_pkey; Type: CONSTRAINT; Schema: public; Owner: inventario
--

ALTER TABLE ONLY public.it_asset_history
    ADD CONSTRAINT it_asset_history_pkey PRIMARY KEY (id);


--
-- Name: it_asset_images it_asset_images_pkey; Type: CONSTRAINT; Schema: public; Owner: inventario
--

ALTER TABLE ONLY public.it_asset_images
    ADD CONSTRAINT it_asset_images_pkey PRIMARY KEY (id);


--
-- Name: it_assets it_assets_pkey; Type: CONSTRAINT; Schema: public; Owner: inventario
--

ALTER TABLE ONLY public.it_assets
    ADD CONSTRAINT it_assets_pkey PRIMARY KEY (id);


--
-- Name: ix_it_asset_history_asset_id; Type: INDEX; Schema: public; Owner: inventario
--

CREATE INDEX ix_it_asset_history_asset_id ON public.it_asset_history USING btree (asset_id);


--
-- Name: ix_it_asset_images_asset_id; Type: INDEX; Schema: public; Owner: inventario
--

CREATE INDEX ix_it_asset_images_asset_id ON public.it_asset_images USING btree (asset_id);


--
-- Name: ix_it_asset_images_filename; Type: INDEX; Schema: public; Owner: inventario
--

CREATE INDEX ix_it_asset_images_filename ON public.it_asset_images USING btree (filename);


--
-- Name: ix_it_assets_asset_tag; Type: INDEX; Schema: public; Owner: inventario
--

CREATE UNIQUE INDEX ix_it_assets_asset_tag ON public.it_assets USING btree (asset_tag);


--
-- Name: ix_it_assets_category; Type: INDEX; Schema: public; Owner: inventario
--

CREATE INDEX ix_it_assets_category ON public.it_assets USING btree (category);


--
-- Name: ix_it_assets_serial_number; Type: INDEX; Schema: public; Owner: inventario
--

CREATE UNIQUE INDEX ix_it_assets_serial_number ON public.it_assets USING btree (serial_number);


--
-- Name: it_asset_history it_asset_history_asset_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: inventario
--

ALTER TABLE ONLY public.it_asset_history
    ADD CONSTRAINT it_asset_history_asset_id_fkey FOREIGN KEY (asset_id) REFERENCES public.it_assets(id) ON DELETE CASCADE;


--
-- Name: it_asset_images it_asset_images_asset_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: inventario
--

ALTER TABLE ONLY public.it_asset_images
    ADD CONSTRAINT it_asset_images_asset_id_fkey FOREIGN KEY (asset_id) REFERENCES public.it_assets(id) ON DELETE CASCADE;


--
-- PostgreSQL database dump complete
--

\unrestrict 6X8mAZhzIDA7xt2wX2EQwcnewFELRjFz1vySVZrd9piqHfeU4wFirxxKaGqhTVG

