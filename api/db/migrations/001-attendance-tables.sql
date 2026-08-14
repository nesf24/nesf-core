-- Create attendance configuration table
CREATE TABLE IF NOT EXISTS attendance_config (
  id SERIAL PRIMARY KEY,
  team_name VARCHAR(100) NOT NULL UNIQUE,
  checkin_start_time TIME NOT NULL,
  checkin_reminder_interval_minutes INT NOT NULL DEFAULT 5,
  checkin_deadline_time TIME NOT NULL,
  checkout_start_time TIME NOT NULL,
  checkout_reminder_interval_minutes INT NOT NULL DEFAULT 5,
  checkout_autocheckin_time TIME NOT NULL,
  enabled BOOLEAN DEFAULT TRUE,
  created_at TIMESTAMP DEFAULT NOW(),
  updated_at TIMESTAMP DEFAULT NOW()
);

-- Create team members mapping
CREATE TABLE IF NOT EXISTS team_members (
  id SERIAL PRIMARY KEY,
  employee_id INT NOT NULL REFERENCES employees(id) ON DELETE CASCADE,
  team_id INT NOT NULL REFERENCES attendance_config(id) ON DELETE CASCADE,
  assigned_at TIMESTAMP DEFAULT NOW(),
  UNIQUE(employee_id, team_id)
);

-- Create device tokens for FCM
CREATE TABLE IF NOT EXISTS device_tokens (
  id SERIAL PRIMARY KEY,
  employee_id INT NOT NULL REFERENCES employees(id) ON DELETE CASCADE,
  fcm_token VARCHAR(500) NOT NULL,
  device_type VARCHAR(50),
  created_at TIMESTAMP DEFAULT NOW(),
  updated_at TIMESTAMP DEFAULT NOW(),
  UNIQUE(employee_id, fcm_token)
);

-- Add indexes
CREATE INDEX idx_team_members_employee ON team_members(employee_id);
CREATE INDEX idx_team_members_team ON team_members(team_id);
CREATE INDEX idx_device_tokens_employee ON device_tokens(employee_id);
CREATE INDEX idx_device_tokens_token ON device_tokens(fcm_token);

-- Insert default team configurations
INSERT INTO attendance_config
  (team_name, checkin_start_time, checkin_reminder_interval_minutes,
   checkin_deadline_time, checkout_start_time, checkout_reminder_interval_minutes,
   checkout_autocheckin_time)
VALUES
  ('Regular Staff', '10:00:00', 5, '10:30:00', '17:00:00', 5, '18:00:00'),
  ('Media Team', '10:00:00', 30, '12:00:00', '22:00:00', 5, '23:00:00')
ON CONFLICT (team_name) DO NOTHING;
