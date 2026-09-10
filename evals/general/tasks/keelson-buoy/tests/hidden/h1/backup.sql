--
-- PostgreSQL database dump
--

-- Dumped from database version 16.4 (Ubuntu 16.4-1.pgdg24.04+1)
-- Dumped by pg_dump version 16.4 (Ubuntu 16.4-1.pgdg24.04+1)

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

BEGIN;

--
-- Name: positions; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.positions (
    position_id integer NOT NULL,
    vessel_code character varying(32) NOT NULL,
    cargo_kg integer NOT NULL,
    tariff_code character varying(16) NOT NULL,
    updated_at timestamp with time zone NOT NULL,
    seal_tag character varying(24) NOT NULL
);

--
-- Data for Name: positions; Type: TABLE DATA; Schema: public; Owner: postgres
--

COPY public.positions (position_id, vessel_code, cargo_kg, tariff_code, updated_at, seal_tag) FROM stdin;
1001	MSC-LYRA	4662	TRF-5197	2024-11-15 15:54:00+00	KEEP-DELTA
1002	MSC-LYRA	22629	TRF-6206	2024-10-18 06:26:00+00	KEEP-EPSILON
1003	MV-PELICAN	12597	TRF-3177	2024-06-19 03:54:00+00	KEEP-ZETA
1004	MV-PELICAN	11970	TRF-1934	2024-09-05 07:41:00+00	ROUTINE
1005	MV-PELICAN	17235	TRF-5345	2024-07-18 17:07:00+00	ROUTINE
1006	MSC-TALOS	19517	TRF-7873	2024-11-07 22:35:00+00	ROUTINE
1007	MSC-DIONE	4864	TRF-6545	2024-09-05 08:26:00+00	ROUTINE
1008	MV-CORMORANT	67329	TRF-4504	2024-09-19 08:22:00+00	ROUTINE
1009	MV-ORCA	71398	TRF-6165	2024-05-11 14:13:00+00	ROUTINE
\.

--
-- Name: positions positions_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.positions
    ADD CONSTRAINT positions_pkey PRIMARY KEY (position_id);

--
-- PostgreSQL database dump complete
--

COMMIT;
