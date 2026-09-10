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
1001	MV-SOREL	84725	TRF-4292	2024-11-08 06:30:00+00	KEEP-ALPHA
1002	MV-CALDER	79883	TRF-4971	2024-08-01 22:30:00+00	KEEP-BETA
1003	MV-TRITON	9778	TRF-3279	2024-05-04 22:16:00+00	ROUTINE
1004	MSC-ERIDANUS	17916	TRF-5050	2024-10-01 11:46:00+00	ROUTINE
1005	CS-NORFOLK	67058	TRF-8780	2024-06-07 13:44:00+00	ROUTINE
1006	MV-CALDER	29442	TRF-7283	2024-06-26 18:09:00+00	ROUTINE
1007	MV-SOREL	41954	TRF-1475	2024-06-09 05:02:00+00	ROUTINE
1008	CS-NORFOLK	58835	TRF-0603	2024-10-04 06:17:00+00	ROUTINE
1009	MV-CALDER	6202	TRF-5327	2024-07-18 07:17:00+00	ROUTINE
1010	MV-SOREL	26195	TRF-7117	2024-06-11 18:17:00+00	ROUTINE
1011	MSC-BANSHEE	66477	TRF-4413	2024-05-06 18:02:00+00	ROUTINE
1012	MSC-BANSHEE	66590	TRF-3599	2024-09-28 20:08:00+00	ROUTINE
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
