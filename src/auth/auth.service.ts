import { Injectable, UnauthorizedException } from '@nestjs/common';
import { JwtService } from '@nestjs/jwt';
import { compare } from 'bcrypt';
import { PrismaService } from '../database/prisma.service';
import { LoginDto } from './dto/login.dto';
import { JwtPayload } from './interfaces/jwt-payload.interface';

@Injectable()
export class AuthService {
  constructor(
    private readonly prisma: PrismaService,
    private readonly jwtService: JwtService,
  ) {}

  async login(dto: LoginDto) {
    const email = dto.email.trim().toLowerCase();
    const user = await this.prisma.users.findUnique({
      where: { email },
    });

    if (!user || !user.is_active) {
      throw new UnauthorizedException('Credenciales inválidas.');
    }

    const passwordMatches = await compare(dto.password, user.password_hash);

    if (!passwordMatches) {
      throw new UnauthorizedException('Credenciales inválidas.');
    }

    const payload: JwtPayload = {
      sub: String(user.id),
      email: user.email,
      role: String(user.role),
    };

    const accessToken = await this.jwtService.signAsync(payload);

    return {
      accessToken,
      tokenType: 'Bearer',
      user: {
        id: String(user.id),
        email: user.email,
        fullName: user.name,
        role: String(user.role),
      },
    };
  }
}
