-- AdventureBoots 2022
AddCSLuaFile()
ENT.Type = "anim"
ENT.Author = "AdventureBoots"
ENT.Category = "JMod - EZ HL:2"
ENT.Information = "Magnum Opus"
ENT.PrintName = "EZ Hopper Mine"
ENT.NoSitAllowed = true
ENT.Spawnable = true
ENT.AdminSpawnable = true
---
ENT.JModGUIcolorable = false
ENT.JModEZstorable = true
ENT.EZscannerDanger = true
ENT.JModPreferredCarryAngles = Angle(0, 0, 0)

ENT.BlacklistedNPCs = {"bullseye_strider_focus", "npc_turret_floor", "npc_turret_ceiling", "npc_turret_ground"}

ENT.WhitelistedNPCs = {"npc_rollermine"}

---
local STATE_BROKEN, STATE_OFF, STATE_ARMING, STATE_ARMED, STATE_LAUNCHED = -1, 0, 1, 2, 3

function ENT:SetupDataTables()
	self:NetworkVar("Int", 0, "State")
	self:NetworkVar("Entity", 0, "Target")
	self:NetworkVar("Bool", 0, "Ally")
end

---
if SERVER then
	function ENT:SpawnFunction(ply, tr)
		local SpawnPos = tr.HitPos + tr.HitNormal * 40
		local ent = ents.Create(self.ClassName)
		ent:SetAngles(Angle(0, 0, 0))
		ent:SetPos(SpawnPos)
		JMod.Owner(ent, ply)
		ent:Spawn()
		ent:Activate()

		return ent
	end

	function ENT:Initialize()
		self:SetModel("models/props_combine/combine_mine01.mdl")
		--self:SetMaterial("models/jacky_camouflage/digi2")
		self:PhysicsInit(SOLID_VPHYSICS)
		self:SetMoveType(MOVETYPE_VPHYSICS)
		self:SetSolid(SOLID_VPHYSICS)
		self:DrawShadow(true)
		self:SetUseType(SIMPLE_USE)
		self:GetPhysicsObject():SetMass(20)
		---
		timer.Simple(.01, function()
			self:GetPhysicsObject():SetMass(10)
			self:GetPhysicsObject():Wake()
		end)
		---
		self:SetState(STATE_OFF)
		---
		if istable(WireLib) then
			self.Inputs = WireLib.CreateInputs(self, {"Detonate", "Arm"}, {"This will directly detonate the bomb", "Arms bomb when > 0"})
			self.Outputs = WireLib.CreateOutputs(self, {"State"}, {"1 is armed \n 0 is not \n -1 is broken \n 2 is arming \n 3 is warning"})
		end
		---
		self.StillTicks = 0
		self.AutoArm = false

		self:SetLegs(70)
		self:SetClaws(-70)

		if self.AutoArm then
			self:NextThink(CurTime() + .3)
		end
		self.WarningSnd = CreateSound(self, "npc/roller/mine/combine_mine_active_loop1.wav")
	end

	function ENT:TriggerInput(iname, value)
		if iname == "Detonate" and value > 0 then
			self:Detonate()
		elseif iname == "Arm" and value > 0 then
			self:Arm(self.Owner or game.GetWorld())
		end
	end

	function ENT:SetLegs(angle)
		self:ManipulateBoneAngles(1,Angle(0,0,angle))
		self:ManipulateBoneAngles(3,Angle(0,0,angle))
		self:ManipulateBoneAngles(5,Angle(0,0,angle))
	end

	function ENT:SetClaws(angle)
		self:ManipulateBoneAngles(2,Angle(0,angle,0))
		self:ManipulateBoneAngles(4,Angle(0,angle,0))
		self:ManipulateBoneAngles(6,Angle(0,angle,0))
		--sound.Play("snd_jack_metallicclick.wav", self:GetPos(), 70, 110)
	end

	function ENT:OnTakeDamage(dmginfo)
		self:TakePhysicsDamage(dmginfo)

		if JMod.LinCh(dmginfo:GetDamage(), 10, 50) then
			local Pos, State = self:GetPos(), self:GetState()

			if State == STATE_WARNING then
				self:Detonate()
			elseif not (State == STATE_BROKEN) then
				sound.Play("Metal_Box.Break", Pos)
				self:SetState(STATE_BROKEN)
				SafeRemoveEntityDelayed(self, 10)
			end
		end
	end

	local ArmAttempts = 0

	function ENT:Use(activator)
		local State = self:GetState()
		if State < 0 then return end
		self.AutoArm = false
		local Alt = activator:KeyDown(JMod.Config.AltFunctionKey)

		if State == STATE_OFF then
			if Alt then
				JMod.Owner(self, activator)
				if self.JModGUIcolorable then
					net.Start("JMod_ColorAndArm")
					net.WriteEntity(self)
					net.Send(activator)
				else
					self:Arm(self.activator)
				end
			else
				activator:PickupObject(self)
				JMod.Hint(activator, "arm")
			end
		elseif not (activator.KeyDown and activator:KeyDown(IN_SPEED)) then
			self:EmitSound("snd_jack_minearm.wav", 60, 70)
			self:SetState(STATE_OFF)
			JMod.Owner(self, activator)
			self:DrawShadow(true)
		end
	end

	function ENT:PhysicsCollide(data, physobj)
		if data.DeltaTime > 0.2 then
			if data.Speed > 10 then
				if self:GetState() == STATE_LAUNCHED then
					self:Detonate()
				else
					self:EmitSound("Weapon.ImpactHard")
				end
			end
		end
	end

	function ENT:Detonate()
		if self.Exploded then return end
		self.Exploded = true
		local SelfPos = self:LocalToWorld(self:OBBCenter())
		local Up = Vector(0, 0, 1)
		local EffectType = 1
		local Traec = util.QuickTrace(self:GetPos(), Vector(0, 0, -5), self)

		if Traec.Hit then
			if (Traec.MatType == MAT_DIRT) or (Traec.MatType == MAT_SAND) then
				EffectType = 1
			elseif (Traec.MatType == MAT_CONCRETE) or (Traec.MatType == MAT_TILE) then
				EffectType = 2
			elseif (Traec.MatType == MAT_METAL) or (Traec.MatType == MAT_GRATE) then
				EffectType = 3
			elseif Traec.MatType == MAT_WOOD then
				EffectType = 4
			end
		else
			EffectType = 5
		end

		local plooie = EffectData()
		plooie:SetOrigin(SelfPos)
		plooie:SetScale(1)
		plooie:SetRadius(EffectType)
		plooie:SetNormal(Up)
		util.Effect("eff_jack_minesplode", plooie, true, true)
		util.ScreenShake(SelfPos, 99999, 99999, 1, 500)
		self:EmitSound("snd_jack_fragsplodeclose.wav", 90, 100)
		JMod.Sploom(self.Owner, SelfPos, math.random(50, 100))
		--JMod.FragSplosion(self, SelfPos, 1000, 20 * JMod.Config.MinePower, 3000, self.Owner, Up, 1.2, 3)
		self:Remove()
	end

	function ENT:Arm(armer)
		local State = self:GetState()
		if State ~= STATE_OFF then return end
		JMod.Hint(armer, "mine friends")
		JMod.Owner(self, armer)
		self:SetState(STATE_ARMING)
		--self:EmitSound("snd_jack_minearm.wav", 60, 110)

		timer.Simple(1, function()
			if IsValid(self) then
				if self:GetState() == STATE_ARMING then
					local Tr = util.QuickTrace(self:GetPos(), Vector(0, 0, -2), self)

					if Tr.Hit then
						self.Weld = constraint.Weld(Tr.Entity, self, 0, 0, 5000, false, false)
						if self.Weld then
							self.Weld:Activate()
							self:SetLegs(0)
							self:SetClaws(0)
							self:EmitSound("npc/roller/blade_cut.wav", 100)
							self:SetState(STATE_ARMED)
							self:DrawShadow(false)
							ArmAttempts = 0
						end
					else
						self:Jump()
						JPrint("ArmAttempts: " .. ArmAttempts )
					end
					self:NextThink(CurTime() + .5)
				end
			end
		end)
	end

	function ENT:Disarm()
		self.WarningSnd:Stop()
		self:EmitSound("npc/roller/mine/combine_mine_deactivate1.wav")
		self:SetState(STATE_OFF)
		self:SetLegs(75)
		self:SetClaws(-75)
	end

	function ENT:Jump()
		local Phys = self:GetPhysicsObject()

		if Phys:IsMotionEnabled() then
			self:EmitSound("npc/roller/mine/rmine_blip3.wav")
			Phys:ApplyForceOffset(Vector(0, 0, 3000), self:LocalToWorld(Vector(math.random()*2, math.random()*2, 0)))
		end
		timer.Simple(1, function()
			if IsValid(self) and (self:GetState() == STATE_ARMING) and (ArmAttempts < 5) then
				ArmAttempts = ArmAttempts + 1
				self:SetState(STATE_OFF)
				self:Arm(JMod.Owner(self) or game.GetWorld())
			else
				self:SetState(STATE_OFF)
			end
		end)
	end

	function ENT:Launch(targetPos)
		self:SetState(STATE_LAUNCHED)
		local SelfPos = self:GetPos()
		local ToVec = targetPos - SelfPos
		ToVec.z = 0
		local ToDir = ToVec:GetNormalized()
		local ToAng = ToDir:Angle()
		ToAng:RotateAroundAxis(ToAng:Right(), 66)
		ToDir = ToAng:Forward() 
		local Dist = SelfPos:Distance(targetPos)
		-----
		local Speed = math.sqrt((600 * Dist) / math.sin(2 * math.rad(66))) -- Fancy math
		-----
		constraint.RemoveAll(self)

		local Phys = self:GetPhysicsObject()

		Phys:EnableMotion(true)
		Phys:SetDragCoefficient(0)
		Phys:SetVelocity(ToDir * Speed)
	end


	function ENT:Think()
		local SelfPos, State, Time = self:GetPos(), self:GetState(), CurTime()

		if istable(WireLib) then
			WireLib.TriggerOutput(self, "State", State)
		end

		if State == STATE_ARMED then
			if not(IsValid(self.Weld)) then
				self:Disarm()
			end
			JPrint(tostring(self:GetTarget()) .. " \t " .. tostring(self:GetAlly()))

			for k, targ in pairs(ents.FindInSphere(SelfPos, 200)) do
				if not (targ == self) and (targ:IsPlayer() or targ:IsNPC() or targ:IsVehicle()) and JMod.ClearLoS(self, targ) then
					
					local targPos = targ:GetPos()

					if not(IsValid(self:GetTarget())) or SelfPos:Distance(self:GetTarget():GetPos()) > SelfPos:Distance(targPos) then
						if JMod.ShouldAttack(self, targ) then
							self.WarningSnd:Play()
							self:SetAlly(false)
						else
							self.WarningSnd:Stop()
							self:SetAlly(true)
						end
						self:SetTarget(targ)
					end
				end
			end

			if IsValid(self:GetTarget()) then
				local Target, TargetPos = self:GetTarget(), self:GetTarget():GetPos()

				if SelfPos:Distance(TargetPos) < 150 then
					if not(self:GetAlly()) then
						self.WarningSnd:Stop()
						self:EmitSound("npc/roller/blade_in.wav")
						self:SetLegs(70)
						self:SetClaws(-70)
						timer.Simple(0.2 * JMod.Config.MineDelay, function()
							if IsValid(self) then
								self:EmitSound("npc/roller/mine/rmine_blip3.wav")
								local LaunchPos = Target:LocalToWorld(Target:OBBCenter()) + Target:GetVelocity()
								self:Launch(LaunchPos)
							end
						end)
					end
				elseif SelfPos:Distance(TargetPos) > 200 then
					self:SetTarget(nil)
					self:SetAlly(false)
					if self.WarningSnd:IsPlaying() then
						self.WarningSnd:Stop()
						self:EmitSound("npc/roller/mine/combine_mine_deactivate1.wav")
					end
				end
			end

			self:NextThink(Time + .3)

			return true
		elseif self.AutoArm then
			local Vel = self:GetPhysicsObject():GetVelocity()

			if Vel:Length() < 1 then
				self.StillTicks = self.StillTicks + 1
			else
				self.StillTicks = 0
			end

			if self.StillTicks > 4 then
				self:Arm(JMod.Owner(self) or game.GetWorld())
			end

			self:NextThink(Time + .1)

			return true
		end
	end

	function ENT:OnRemove()
		self.WarningSnd:Stop()
	end

elseif CLIENT then
	function ENT:Initialize()
	end

	--
	local GlowSprite = Material("sprites/mat_jack_basicglow")

	function ENT:Draw()
		self:DrawModel()
		local Up = self:GetUp()
		local State= self:GetState()

		if State == STATE_ARMING then
			render.SetMaterial(GlowSprite)
			render.DrawSprite(self:GetPos() + Up * 10, 20, 20, Color(0, 0, 255))
			render.DrawSprite(self:GetPos() + Up * 10, 10, 10, Color(0, 0, 255))
		elseif State == STATE_ARMED then
			if IsValid(self:GetTarget()) and self:GetAlly() then
				render.SetMaterial(GlowSprite)
				render.DrawSprite(self:GetPos() + Up * 10, 20, 20, Color(0, 255, 0))
				render.DrawSprite(self:GetPos() + Up * 10, 15, 15, Color(0, 255, 0))
			elseif IsValid(self:GetTarget()) and (self:GetAlly() == false) then
				render.SetMaterial(GlowSprite)
				render.DrawSprite(self:GetPos() + Up * 10, 20, 20, Color(255, 0, 0))
				render.DrawSprite(self:GetPos() + Up * 10, 15, 15, Color(255, 0, 0))
			elseif not(IsValid(self:GetTarget())) then
				render.SetMaterial(GlowSprite)
				render.DrawSprite(self:GetPos() + Up * 10, 20, 20, Color(255, 255, 0))
				render.DrawSprite(self:GetPos() + Up * 10, 15, 15, Color(255, 255, 0))
			end
		end
	end

	language.Add("ent_jack_gmod_ezhoppermine", "EZ Hopper Mine")
end



--[[
	----Combine mine behavior, for refrence----
	1)Start arming (about 1 sec delay)
	2)Trace downward
	2a)If hit, grab with claws and arm like normal
	2b)If not hit, jump, and go to step 2
	3)If applicible entity comes into range and sight, set as target
	3a)If target is enemy, turn red and start warning
	3b)If target ally, turn green and give no indicative sound
	3c)If there are no applicible targets in range, set target to nil and go to step 3
	4)If target gets to close and is enemy, disengage from the ground (about .5 delay)
	5)Blip and jump towards target
	
	----Below are rules for whatever state the mine is in----

	Rule 1)If picked up with the grav-gun, turn yellow (about 1 sec delay) 'disarm' and set to players side
	Rule 1a)While being held, turn light blue and actuate claws
	Rule 2)If dropped, go to step 1
	Rule 3)If thrown at any great speed, explode
]]--