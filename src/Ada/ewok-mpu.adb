--
-- Copyright 2018 The wookey project team <wookey@ssi.gouv.fr>
--   - Ryad     Benadjila
--   - Arnauld  Michelizza
--   - Mathieu  Renard
--   - Philippe Thierry
--   - Philippe Trebuchet
--
-- Licensed under the Apache License, Version 2.0 (the "License");
-- you may not use this file except in compliance with the License.
-- You may obtain a copy of the License at
--
--     http://www.apache.org/licenses/LICENSE-2.0
--
--     Unless required by applicable law or agreed to in writing, software
--     distributed under the License is distributed on an "AS IS" BASIS,
--     WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
--     See the License for the specific language governing permissions and
--     limitations under the License.
--
--


with ada.unchecked_conversion;

with m4.mpu;   use m4.mpu;
with ewok.mpu.handler;
with ewok.layout;
with ewok.debug;
with soc.layout;
with applications; -- generated

package body ewok.mpu
  with spark_mode => on
is

   procedure init
     (success : out boolean)
     with spark_mode => off  -- handler is not SPARK compatible
   is
      -- Layout mapping validation of generated constants
      pragma assert
        (applications.txt_kern_size + applications.txt_kern_region_base
            <= applications.txt_user_region_base);

      function get_region_size (size : t_region_size) return unsigned_32
         is (2**(natural (size) + 1));

      region_config  : m4.mpu.t_region_config;
   begin

      --
      -- Initializing the MPU
      --

      -- Testing if there's an MPU
      m4.mpu.is_mpu_available (success);

      if not success then
         pragma DEBUG (debug.log (debug.ERROR, "No MPU!"));
         return;
      end if;

      -- Register memory fault handler
      -- Note: unproved because SPARK doesn't allow "'address" attribute
      ewok.mpu.handler.init; -- not PARK compatible

      -- Disable MPU
      m4.mpu.disable;

      -- Enable privileged software access (PRIVDEFENA) to default memory map
      -- and enable the memory fault exception. When ENABLE and PRIVDEFENA are
      -- both set to 1, privileged code can freely access the default memory
      -- map. Any access by unprivileged software that does not address an
      -- enabled memory region causes a memory management fault.
      m4.mpu.init;

      --
      -- Configuring MPU regions
      --

      -- Region: kernel code
      if get_region_size (REGION_SIZE_64KB) /= ewok.layout.FW1_KERN_SIZE then
         pragma DEBUG
           (debug.log (debug.ERROR, "MPU: invalid 'KERNEL CODE' size"));
         return;
      end if;

      region_config :=
        (region_number  => KERN_CODE_REGION,
         addr           => applications.txt_kern_region_base,
         size           => applications.txt_kern_region_size,
         subregion_mask => 0,
         access_perm    => REGION_PERM_PRIV_RO_USER_NO,
         xn             => false,
         b              => false,
         s              => false);

      m4.mpu.configure_region (region_config);

      -- Region: devices that may be accessed by the kernel
      region_config :=
        (region_number  => KERN_DEVICES_REGION,
         addr           => soc.layout.PERIPH_BASE,
         size           => REGION_SIZE_512MB,
         subregion_mask => 0,
         access_perm    => REGION_PERM_PRIV_RW_USER_NO,
         xn             => true,
         b              => true,
         s              => true);

      m4.mpu.configure_region (region_config);

      -- Region: kernel data + stack
      if get_region_size (REGION_SIZE_64KB) /= ewok.layout.KERN_DATA_SIZE then
         pragma DEBUG
           (debug.log (debug.ERROR, "MPU: invalid 'KERNEL DATA' size"));
         return;
      end if;

      region_config :=
        (region_number  => KERN_DATA_REGION,
         addr           => ewok.layout.KERN_DATA_BASE,
         size           => REGION_SIZE_64KB,
         subregion_mask => 0,
         access_perm    => REGION_PERM_PRIV_RW_USER_NO,
         xn             => true,
         b              => false,
         s              => true);

      m4.mpu.configure_region (region_config);

      -- Region: user data
      -- Note: This is for the whole area. Each task will use only a fixed
      --       number of sub-regions
      if get_region_size (REGION_SIZE_128KB) /= ewok.layout.USER_RAM_SIZE then
         pragma DEBUG (debug.log (debug.ERROR, "MPU: invalid 'USER DATA' size"));
         return;
      end if;

      region_config :=
        (region_number  => USER_DATA_REGION,
         addr           => ewok.layout.USER_DATA_BASE,
         size           => REGION_SIZE_128KB,
         subregion_mask => 0,
         access_perm    => REGION_PERM_PRIV_RW_USER_RW,
         xn             => true,
         b              => false,
         s              => true);

      m4.mpu.configure_region (region_config);

      -- Region: user code
      -- Note: This is for the whole area. Each task will use only a fixed
      --       number of sub-regions
      if get_region_size (REGION_SIZE_256KB) /= ewok.layout.FW1_USER_SIZE then
         pragma DEBUG (debug.log (debug.ERROR, "MPU: invalid 'USER CODE' size"));
         return;
      end if;

      region_config :=
        (region_number  => USER_CODE_REGION,
         addr           => applications.txt_user_region_base,
         size           => applications.txt_user_region_size,
         subregion_mask => 0,
         access_perm    => REGION_PERM_PRIV_RO_USER_RO,
         xn             => false,
         b              => false,
         s              => false);

      m4.mpu.configure_region (region_config);

      -- Region: user ISR stack
      region_config :=
        (region_number  => USER_ISR_STACK_REGION,
         addr           => ewok.layout.STACK_BOTTOM_TASK_ISR,
         size           => REGION_SIZE_4KB,
         subregion_mask => 0,
         access_perm    => REGION_PERM_PRIV_RW_USER_RW,
         xn             => true,
         b              => false,
         s              => true);

      m4.mpu.configure_region (region_config);

      pragma DEBUG (debug.log (debug.INFO, "MPU is configured"));
      m4.mpu.enable;
      pragma DEBUG (debug.log (debug.INFO, "MPU is enabled"));

   end init;


   procedure enable_unrestricted_kernel_access
   is
   begin
      m4.mpu.enable_unrestricted_kernel_access;
   end enable_unrestricted_kernel_access;


   procedure disable_unrestricted_kernel_access
   is
   begin
      m4.mpu.disable_unrestricted_kernel_access;
   end disable_unrestricted_kernel_access;


   procedure regions_schedule
     (region_number  : in  m4.mpu.t_region_number;
      addr           : in  system_address;
      size           : in  m4.mpu.t_region_size;
      region_type    : in  t_region_type;
      subregion_mask : in  unsigned_8)
   is
      region_config  : m4.mpu.t_region_config;
   begin
      -- A memory region must never be mapped RWX
      case (region_type) is
         when REGION_TYPE_USER_DEV =>
            region_config :=
              (region_number  => region_number,
               addr           => addr,
               size           => size,
               subregion_mask => subregion_mask,
               access_perm    => REGION_PERM_PRIV_RW_USER_RW,
               xn             => true,
               b              => true,
               s              => true);

            m4.mpu.configure_region (region_config);

         when REGION_TYPE_RO_USER_DEV =>
            region_config :=
              (region_number  => region_number,
               addr           => addr,
               size           => size,
               subregion_mask => subregion_mask,
               access_perm    => REGION_PERM_PRIV_RW_USER_RO,
               xn             => true,
               b              => true,
               s              => true);

            m4.mpu.configure_region (region_config);

         when REGION_TYPE_USER_CODE =>
            region_config :=
              (region_number  => region_number,
               addr           => addr,
               size           => size,
               subregion_mask => subregion_mask,
               access_perm    => REGION_PERM_PRIV_RO_USER_RO,
               xn             => false,
               b              => false,
               s              => false);

            m4.mpu.update_subregion_mask (region_config);

         when REGION_TYPE_USER_DATA =>
            region_config :=
              (region_number  => region_number,
               addr           => addr,
               size           => size,
               subregion_mask => subregion_mask,
               access_perm    => REGION_PERM_PRIV_RW_USER_RW,
               xn             => true,
               b              => false,
               s              => true);

            m4.mpu.update_subregion_mask (region_config);

         when REGION_TYPE_BOOT_ROM =>

            -- MPU makes Boot ROM region unattainable to avoid ROP attacks

            region_config :=
              (region_number  => region_number,
               addr           => addr,
               size           => size,
               subregion_mask => 0,
               access_perm    => REGION_PERM_PRIV_NO_USER_NO,
               xn             => true,
               b              => false,
               s              => false);

            m4.mpu.configure_region (region_config);

         when REGION_TYPE_ISR_DATA =>
            region_config :=
              (region_number  => region_number,
               addr           => addr,
               size           => size,
               subregion_mask => 0,
               access_perm    => REGION_PERM_PRIV_RW_USER_RW,
               xn             => true,
               b              => false,
               s              => true);

            m4.mpu.configure_region (region_config);

      end case;

   end regions_schedule;


   procedure bytes_to_region_size
     (bytes       : in  unsigned_32;
      region_size : out m4.mpu.t_region_size;
      success     : out boolean)
   is
   begin
      success := true;
      case (bytes) is
         when 32        => region_size := REGION_SIZE_32B;
         when 64        => region_size := REGION_SIZE_64B;
         when 128       => region_size := REGION_SIZE_128B;
         when 256       => region_size := REGION_SIZE_256B;
         when 512       => region_size := REGION_SIZE_512B;
         when 1*KBYTE   => region_size := REGION_SIZE_1KB;
         when 2*KBYTE   => region_size := REGION_SIZE_2KB;
         when 4*KBYTE   => region_size := REGION_SIZE_4KB;
         when 8*KBYTE   => region_size := REGION_SIZE_8KB;
         when 16*KBYTE  => region_size := REGION_SIZE_16KB;
         when 32*KBYTE  => region_size := REGION_SIZE_32KB;
         when 64*KBYTE  => region_size := REGION_SIZE_64KB;
         when 128*KBYTE => region_size := REGION_SIZE_128KB;
         when 256*KBYTE => region_size := REGION_SIZE_256KB;
         when 512*KBYTE => region_size := REGION_SIZE_512KB;
         when 1*MBYTE   => region_size := REGION_SIZE_1MB;
         when 2*MBYTE   => region_size := REGION_SIZE_2MB;
         when 4*MBYTE   => region_size := REGION_SIZE_4MB;
         when 8*MBYTE   => region_size := REGION_SIZE_8MB;
         when 16*MBYTE  => region_size := REGION_SIZE_16MB;
         when 32*MBYTE  => region_size := REGION_SIZE_32MB;
         when 64*MBYTE  => region_size := REGION_SIZE_64MB;
         when 128*MBYTE => region_size := REGION_SIZE_128MB;
         when 256*MBYTE => region_size := REGION_SIZE_256MB;
         when 512*MBYTE => region_size := REGION_SIZE_512MB;
         when 1*GBYTE   => region_size := REGION_SIZE_1GB;
         when 2*GBYTE   => region_size := REGION_SIZE_2GB;
         when others    =>
            region_size := REGION_SIZE_32B;
            success     := false;
      end case;
   end bytes_to_region_size;

end ewok.mpu;
