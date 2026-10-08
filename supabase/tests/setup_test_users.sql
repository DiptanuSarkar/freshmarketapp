DO $$
DECLARE
  v_pass text;
  v_bob_id uuid := 'd28a286e-566f-4eb5-8c0b-265551b5ad19';
  v_ident_id uuid := 'f242c5d0-2e8a-4180-a26b-026cd86c35ae';
BEGIN
  SELECT encrypted_password INTO v_pass FROM auth.users WHERE email = 'alice.customer.test@gmail.com';

  INSERT INTO auth.users (
    id, instance_id, aud, role, email, encrypted_password, email_confirmed_at,
    raw_app_meta_data, raw_user_meta_data, created_at, updated_at
  ) VALUES (
    v_bob_id, '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated',
    'bob.customer.test@gmail.com', v_pass, now(),
    '{"provider":"email","providers":["email"]}'::jsonb,
    '{"full_name":"Bob Customer"}'::jsonb,
    now(), now()
  ) ON CONFLICT (id) DO NOTHING;

  INSERT INTO auth.identities (
    id, provider_id, user_id, identity_data, provider, last_sign_in_at, created_at, updated_at
  ) VALUES (
    v_ident_id, v_bob_id::text, v_bob_id,
    jsonb_build_object('sub', v_bob_id, 'email', 'bob.customer.test@gmail.com', 'email_verified', true, 'phone_verified', false),
    'email', now(), now(), now()
  ) ON CONFLICT (id) DO NOTHING;

  -- Ensure Bob has a cart and an address
  INSERT INTO public.carts (id, user_id)
  VALUES ('c2000000-0000-0000-0000-000000000002', v_bob_id)
  ON CONFLICT DO NOTHING;

  INSERT INTO public.addresses (
    id, user_id, label, recipient_name, phone, address_line1, city, state, pincode, is_default
  ) VALUES (
    'ad000000-0000-0000-0000-000000000002', v_bob_id, 'Home', 'Bob Customer', '+919876543211',
    '456 5th Block, Koramangala', 'Bengaluru', 'Karnataka', '560034', true
  ) ON CONFLICT (id) DO UPDATE SET user_id = v_bob_id;

  -- Ensure Alice has a cart and address linked to her confirmed ID
  INSERT INTO public.carts (id, user_id)
  VALUES ('c2000000-0000-0000-0000-000000000001', 'c18a286e-566f-4eb5-8c0b-265551b5ad18')
  ON CONFLICT DO NOTHING;

  INSERT INTO public.addresses (
    id, user_id, label, recipient_name, phone, address_line1, city, state, pincode, is_default
  ) VALUES (
    'ad000000-0000-0000-0000-000000000001', 'c18a286e-566f-4eb5-8c0b-265551b5ad18', 'Home', 'Alice Customer', '+919876543210',
    '123 4th Cross, 100 Feet Rd, Indiranagar', 'Bengaluru', 'Karnataka', '560038', true
  ) ON CONFLICT (id) DO UPDATE SET user_id = 'c18a286e-566f-4eb5-8c0b-265551b5ad18';
END $$;
